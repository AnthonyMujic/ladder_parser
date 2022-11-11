defmodule ParseApp do
  use Application

  def start(_type, _args) do
    Task.start(fn -> LadderParser.run() end)
  end
end
