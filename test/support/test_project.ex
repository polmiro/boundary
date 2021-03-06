# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Boundary.TestProject do
  @moduledoc false

  def in_project(opts \\ [], fun) do
    loaded_apps_before = Enum.into(Application.loaded_applications(), MapSet.new(), fn {app, _, _} -> app end)
    %{name: name, file: file} = Mix.Project.pop()
    tmp_path = Path.absname("tmp/#{:erlang.unique_integer(~w/positive monotonic/a)}")

    app_name = "test_project_#{:erlang.unique_integer(~w/positive monotonic/a)}"
    app = String.to_atom(app_name)
    project = %{app: app, path: Path.join(tmp_path, app_name)}

    try do
      File.rm_rf(project.path)

      Mix.Task.clear()
      :ok = Mix.Tasks.New.run([project.path])
      reinitialize(project, opts)

      Mix.Project.in_project(app, project.path, [], fn _module -> fun.(project) end)
    after
      Mix.Project.push(name, file)

      Application.loaded_applications()
      |> Enum.into(MapSet.new(), fn {app, _, _} -> app end)
      |> MapSet.difference(loaded_apps_before)
      |> Enum.each(&Application.unload/1)

      File.rm_rf(tmp_path)
    end
  end

  def compile do
    result = run_task("compile", ["--return-errors"])
    {warnings, result} = Map.pop!(result, :result)
    Map.put(result, :warnings, warnings)
  end

  def run_task(task, args \\ []) do
    ref = make_ref()

    ExUnit.CaptureIO.capture_io(:stderr, fn ->
      Mix.Task.clear()
      send(self(), {ref, Mix.Task.run(task, args)})
    end)

    receive do
      {^ref, result} ->
        result =
          case result do
            :ok -> []
            {:ok, result} -> result
          end

        output =
          Stream.repeatedly(fn ->
            receive do
              {:mix_shell, :info, msg} -> msg
            after
              0 -> nil
            end
          end)
          |> Enum.take_while(&(not is_nil(&1)))
          |> to_string

        %{result: result, output: output}
    after
      0 -> raise("result not received")
    end
  end

  defp reinitialize(project, opts) do
    File.write!(Path.join(project.path, "mix.exs"), mix_exs(project.app, Keyword.get(opts, :mix_opts, [])))
    File.rm_rf(Path.join(project.path, "lib"))
    File.mkdir_p!(Path.join(project.path, "lib"))
  end

  defp mix_exs(project_name, opts) do
    """
    defmodule #{Macro.camelize(to_string(project_name))}.MixProject do
      use Mix.Project

      def project do
        [
          app: :#{project_name},
          version: "0.1.0",
          elixir: "~> 1.10",
          start_permanent: Mix.env() == :prod,
          deps: deps(),
          compilers: #{inspect(Keyword.get(opts, :compilers, [:boundary]))} ++ Mix.compilers()
        ] ++ #{inspect(Keyword.get(opts, :project_opts, []))}
      end

      def application do
        [
          extra_applications: [:logger]
        ]
      end

      defp deps do
        #{inspect(Keyword.get(opts, :deps, [{:boundary, path: unquote(Path.absname("."))}]))}
      end
    end
    """
  end
end
