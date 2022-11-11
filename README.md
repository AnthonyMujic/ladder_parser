# LadderParser

**PLC ladder logic parser that converts 2D ASCII text into Elixir code**

## Getting started

To run this code you will need [elixir installed](https://elixir-lang.org/install.html).

Clone this repo, or download the code. 

From within the repository pull down the dependencies, start iex and run the code:
```
mix deps.get
iex -S mix
LadderParser.run()
```
The output should show:
```elixir
iex> LadderParser.run()

    |     X1            X2                  Y1
    [------] [----+------] [----------------(   )----
    |             |
    |     X3      |
    [------]/[----+
    

result: {true, [y1: true, x3: false, x2: true, x1: false]}
%{
  metadata: %{
    ast: {:=, [line: 1],
     [
       {:y1, [line: 1], nil},
       {:and, [line: 1],
        [
          {:or, [line: 1],
           [
             {:x1, [line: 1], nil},
             {:__block__, [line: 1, line: 1],
              [{:not, [line: 1], [{:x3, [line: 1], nil}]}]}
           ]},
          {:x2, [line: 1], nil}
        ]}
     ]},
    elixir_expression: "y1 = ((x1) or (( not x3))) and (x2)",
    output: ["Y1"]
  },
  rung: #Nx.Tensor<
    s64[rows: 2][columns: 38]
    [
      [32, 32, 32, 32, 32, 32, 32, 32, 32, 88, 49, 32, 32, 32, 32, 32, 32, 32, 43, 32, 32, 32, 32, 88, 50, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32],
      [32, 32, 32, 32, 32, 32, 32, 32, 32, 33, ...]
    ]
  >
}
```
At the moment, this project is bare bones, but the possibilities are exciting.

``` mermaid
flowchart LR
1-->2-.->3 & 4 & 5
5-.->6
4-.->7
3-.->8
1[Input ladder logic]
2[Elixir AST]
3[Diagrams and documentation]
4[Other PLC dialects]
5[Executable elixir for simulations]
6[Target Nerves devices]
7[ControlLogix/Do-more/Other]
8[Mermaid-js diagrams]
```
## Under the hood
ladder_parser uses [Elixir](https://elixir-lang.org/) and [Nx](https://hexdocs.pm/nx/Nx.html) to convert a two dimensional string into a matrix (tensor). A series of tokens are defined, and the matrix is scanned searching for the tokens. The result is then converted into elixir syntax, which can be represented as an abstract syntax tree (AST). Example values are assigned to the inputs and the logic is executed.

## Possibilities
Having the logic represented as a tree, opens up a number of useful possibilities. It could be used to generate documentation and ladder logic in different dialects, for example in PLC upgrade projects. It could also be used to run simulations locally without a PLC. It could be converted to target a [Nerves](https://www.nerves-project.org/) device rather than a traditional PLC. It could also be used to format the code in a suitable form to explore [the power of prolog](https://youtu.be/8XUutFBbUrg) - for instance, imagine you have a legacy PLC with 10k rungs of spaghetti code and you want to know all possible situations that would cause sequence 18 to transition to step 34.

## Note
I don't have a computer science background, so my terminology may be sloppy. I learnt all I know about parsers from Saša Jurić's fantastic talk [Parsing from first principles - WebCamp Zagreb 2019](https://youtu.be/xNzoerDljjo).
