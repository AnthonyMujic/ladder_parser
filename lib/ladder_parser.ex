defmodule LadderParser do
  require Integer

  def run() do
    input = "
    |     X1            X2                  Y1
    [------] [----+------] [----------------(   )----
    |             |
    |     X3      |
    [------]/[----+
    "

    IO.puts("#{input}\n")

    parse(input)
  end

  defp parse(input) do
    parser = convert_to_tree()
    parser.(input)
  end

  defp convert_to_tree() do
    fn input ->
      rung = to_tensor(input)

      %{rung: rung, metadata: %{output: [], elixir_expression: "", ast: ""}}
      |> replace_token(" €€€€€€€ \n---] [---\n", "         \n €€€€€€€ \n")
      |> replace_token("  €€€€€€ \n---]/[---\n", "         \n !€€€€€€ \n")
      |> extract_output(" €€€€€€ \n---(   )---")
      |> replace_token(" ----- ", "  and  ")
      |> replace_token("-", " ")
      |> replace_token("|", " ")
      |> replace_token("[", " ")
      |> remove_empty_line()
      |> convert_to_elixir_expression()
      |> add_on_trailing_statements()
      |> replace_string("!", " not ")
      |> prepend_outputs()
      |> lower_case()
      |> get_input_ast()
      |> run_rung()
    end
  end

  # Convert a multiline string to a tensor
  # Some lines may be longer than others, so need the longest line length and
  # pad out the shorter lines.
  defp to_tensor(str) do
    rung_lines = String.split(str, "\n", trim: true)

    longest_line =
      rung_lines
      |> Enum.max_by(fn x -> String.length(x) end)
      |> String.length()

    rung_lines
    |> Enum.map(fn x -> String.pad_trailing(x, longest_line) end)
    |> Enum.map(fn x -> to_charlist(x) end)
    |> Nx.tensor(names: [:rows, :columns])
  end

  # Replace a pattern with one that simplifies parsing in future steps.
  # The original string is in regular ascii (0-127). Use extended ascii characters (128 - )
  # to indicate regions of the token that may vary, for instance a contacts address.
  # In the examples I use €.
  defp replace_token(input, token, replacement) do
    {rung_rows, rung_columns} = Nx.shape(input[:rung])
    token_list = list_special_character_groups(token)

    token = to_tensor(token)

    {token_rows, token_columns} = Nx.shape(token)

    needs_to_match = Nx.less(token, 128)

    replacement_list = list_special_character_groups(replacement)

    row_range = 0..(rung_rows - token_rows)
    column_range = 0..(rung_columns - token_columns)

    new_rung =
      Enum.reduce(row_range, input[:rung], fn x, a ->
        Enum.reduce(column_range, a, fn y, b ->
          window = b[rows: x..(x - 1 + token_rows), columns: y..(y - 1 + token_columns)]
          matching_characters = Nx.equal(window, token)
          ba = Nx.not_equal(needs_to_match, matching_characters)
          ba2 = Nx.sum(ba)

          if Nx.to_flat_list(ba2) == [0] do
            token_special_characters = Nx.greater(token, 127)

            window_list =
              Nx.select(
                token_special_characters,
                window,
                to_tensor(" ")
              )
              |> Nx.to_flat_list()
              |> List.to_string()
              |> String.split()

            replacement_window =
              Enum.reduce(replacement_list, replacement, fn x, acc ->
                String.replace(acc, x, fn y ->
                  index = Enum.find_index(token_list, fn z -> z == y end)

                  Enum.at(window_list, index)
                  |> String.pad_trailing(String.length(x))
                end)
              end)
              |> to_tensor()

            Nx.put_slice(b, [x, y], replacement_window)
          else
            b
          end
        end)
      end)

    %{input | rung: new_rung}
  end

  defp extract_output(rung, coil) do
    {rung_rows, rung_columns} = Nx.shape(rung[:rung])

    token = to_tensor(coil)
    {_token_rows, token_columns} = Nx.shape(token)

    row_range = 0..(rung_rows - 1)
    column_range = 0..(rung_columns - token_columns)

    new_rung =
      Enum.reduce(row_range, rung, fn x, a ->
        Enum.reduce(column_range, a, fn y, b ->
          var = Nx.to_flat_list(b[:rung][rows: x - 1, columns: y..(y - 1 + token_columns)])

          var_string =
            var
            |> List.to_string()
            |> String.trim()

          window = b[:rung][rows: x, columns: y..(y - 1 + token_columns)]
          token_instruction = token[rows: 1]

          if token_instruction == window do
            new_output = b[:metadata][:output] ++ [var_string]
            new_metadata = Map.put(b[:metadata], :output, new_output)
            %{b | metadata: new_metadata}
          else
            b
          end
        end)
      end)

    %{new_rung | rung: trim_tensor(new_rung[:rung], 15)}
  end

  defp remove_empty_line(input) do
    {rung_rows, rung_columns} = Nx.shape(input[:rung])
    blank_line = Nx.new_axis(Nx.broadcast(32, {rung_columns}, names: [:columns]), 0, :rows)
    row_range = 0..(rung_rows - 1)

    new_input =
      Enum.reduce(row_range, input, fn x, a ->
        window = Nx.new_axis(a[:rung][rows: x], 0, :rows)

        if window == blank_line do
          a
        else
          if Map.has_key?(a[:metadata], :new_rung) do
            new_rung = Nx.concatenate([a[:metadata][:new_rung], window], axis: :rows)
            new_metadata = %{a[:metadata] | new_rung: new_rung}
            %{a | metadata: new_metadata}
          else
            new_metadata =
              a[:metadata]
              |> Map.put(:new_rung, window)

            %{a | metadata: new_metadata}
          end
        end
      end)

    %{input | rung: new_input[:metadata][:new_rung]}
  end

  defp convert_to_elixir_expression(input) do
    new_input =
      input
      |> find_branch_positions()
      |> split_branch()
      |> inject_and_statements()

    expression = new_input[:metadata][:elixir_expression]

    new_metadata = %{
      input[:metadata]
      | elixir_expression: input[:metadata][:elixir_expression] <> expression
    }

    %{input | metadata: new_metadata}
  end

  defp add_on_trailing_statements(input) do
    {_rows, columns} = Nx.shape(input[:rung])
    i = find_branch_positions(input)

    if i[:metadata][:branch_points] == [] do
      input
    else
      max_branch_point = Enum.max(i[:metadata][:branch_points])

      if columns > max_branch_point do
        trailing_statements =
          i[:rung][rows: 0, columns: (max_branch_point + 1)..-1//1]
          |> Nx.to_flat_list()
          |> List.to_string()
          |> String.trim()

        expression =
          input[:metadata][:elixir_expression] <>
            " and (" <>
            trailing_statements <>
            ")"

        new_metadata = %{input[:metadata] | elixir_expression: expression}
        %{input | metadata: new_metadata}
      else
        input
      end
    end
  end

  defp replace_string(%{rung: rung, metadata: metadata}, token, replacement) do
    expression =
      metadata[:elixir_expression]
      |> String.replace(token, replacement)

    new_metadata = %{metadata | elixir_expression: expression}
    %{rung: rung, metadata: new_metadata}
  end

  defp prepend_outputs(input) do
    expression = input[:metadata][:elixir_expression]
    outputs = Enum.join(input[:metadata][:output], " = ")

    new_expression = outputs <> " = " <> expression

    new_metadata = %{
      input[:metadata]
      | elixir_expression: new_expression
    }

    %{input | metadata: new_metadata}
  end

  defp lower_case(input) do
    expression = String.downcase(input[:metadata][:elixir_expression])

    new_metadata = %{
      input[:metadata]
      | elixir_expression: expression
    }

    %{input | metadata: new_metadata}
  end

  defp get_input_ast(input) do
    ast = Code.string_to_quoted!(input[:metadata][:elixir_expression])

    new_metadata = %{
      input[:metadata]
      | ast: ast
    }

    %{input | metadata: new_metadata}
  end

  defp run_rung(input) do
    Code.eval_string(input[:metadata][:elixir_expression],
      x1: false,
      x2: true,
      x3: false
    )
    |> IO.inspect(label: "result")

    input
  end

  defp list_special_character_groups(token) do
    tensor = to_tensor(token)

    tensor_special_characters = Nx.greater(tensor, 127)

    tensor_special_characters_absent =
      Nx.logical_not(tensor_special_characters)
      |> Nx.multiply(32)

    Nx.select(
      tensor_special_characters,
      tensor,
      tensor_special_characters_absent
    )
    |> Nx.to_flat_list()
    |> List.to_string()
    |> String.split()
  end

  defp branch_position_found?(x, acc) when x == ?+, do: [acc[:index] | acc[:branch_positions]]
  defp branch_position_found?(_x, acc), do: acc[:branch_positions]

  defp find_branch_positions(input) do
    {_rows, columns} = Nx.shape(input[:rung])

    branch_flattened =
      input[:rung][rows: 0, columns: 0..(columns - 1)]
      |> Nx.to_flat_list()

    branch_positions_map =
      branch_flattened
      |> Enum.reduce(
        %{index: 0, branch_positions: []},
        fn x, acc ->
          branch_position_list = branch_position_found?(x, acc)

          %{acc | index: acc[:index] + 1, branch_positions: branch_position_list}
        end
      )

    new_metadata =
      input[:metadata]
      |> Map.put(:branch_points, Enum.sort(branch_positions_map[:branch_positions]))

    %{input | metadata: new_metadata}
  end

  defp split_branch(input) do
    {rows, _columns} = Nx.shape(input[:rung])

    if input[:metadata][:branch_points] == [] or rows == 1 do
      expression =
        Nx.to_flat_list(input[:rung][0][0..-2//1])
        |> List.to_string()
        |> String.trim()

      elixir_expression =
        if expression == "" do
          ""
        else
          "(" <> expression <> ")"
        end

      new_metadata = %{input[:metadata] | elixir_expression: elixir_expression}

      %{input | metadata: new_metadata}
    else
      branch_points = [0 | input[:metadata][:branch_points]]

      Enum.reduce(1..(Enum.count(branch_points) - 1), input, fn x, a ->
        part =
          a[:rung][
            rows: 0..(rows - 1),
            columns: (Enum.at(branch_points, x - 1) + 1)..Enum.at(branch_points, x)
          ]

        {part_rows, _part_columns} = Nx.shape(input[:rung])

        convert_to_string(%{rung: part})

        top_statement =
          Nx.to_flat_list(part[0][0..-2//1])
          |> List.to_string()
          |> String.trim()

        lower_part = part[1..(part_rows - 1)]

        lower_segment =
          %{rung: lower_part, metadata: %{elixir_expression: ""}}
          |> convert_to_elixir_expression()

        expression =
          if lower_segment[:metadata][:elixir_expression] == "" do
            if top_statement == "" do
              ""
            else
              a[:metadata][:elixir_expression] <>
                "(" <>
                top_statement <> ")"
            end
          else
            if lower_segment[:metadata][:elixir_expression] == "" do
              a[:metadata][:elixir_expression] <>
                "((" <>
                top_statement <> "))"
            else
              a[:metadata][:elixir_expression] <>
                "((" <>
                top_statement <>
                ") or (" <> lower_segment[:metadata][:elixir_expression] <> "))"
            end
          end

        new_metadata = %{a[:metadata] | elixir_expression: expression}
        %{a | metadata: new_metadata}
      end)
    end
  end

  defp inject_and_statements(input) do
    ee = input[:metadata][:elixir_expression]
    expression = String.replace(ee, ")(", ") and (")
    new_metadata = %{input[:metadata] | elixir_expression: expression}
    %{input | metadata: new_metadata}
  end

  defp add_line_breaks(rows, input) when rows > 0 do
    line_breaks = Nx.broadcast(10, {rows, 1})
    Nx.concatenate([input[:rung], line_breaks], axis: :columns)
  end

  defp add_line_breaks(_, input), do: input[:rung]

  defp convert_to_string(input) do
    {rows, _columns} = Nx.shape(input[:rung])

    add_line_breaks(rows, input)
    |> Nx.to_flat_list()
  end

  defp trim_tensor(tensor, trim_length) do
    {tensor_rows, tensor_columns} = Nx.shape(tensor)
    tensor[rows: 0..(tensor_rows - 1), columns: 0..(tensor_columns - 1 - trim_length)]
  end
end
