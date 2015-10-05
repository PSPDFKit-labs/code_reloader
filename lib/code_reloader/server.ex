# The GenServer used by the CodeReloader.
defmodule CodeReloader.Server do
  @moduledoc false
  use GenServer

  require Logger
  alias CodeReloader.Proxy

  @name __MODULE__

  def start_link do
    Mix.Project.get!
    app = Mix.Project.config[:app]
    #root = Mix.ProjectStack.peek[:file] |> Path.dirname # Private API!
    root = System.cwd
    IO.inspect Application.get_all_env(:code_reloader)
    paths = Application.fetch_env!(:code_reloader, :reloadable_paths)
    compilers = Application.fetch_env!(:code_reloader, :reloadable_compilers)
    GenServer.start_link(__MODULE__, {app, root, paths, compilers}, name: @name)
  end

  def reload!() do
    GenServer.call(@name, :reload!, :infinity)
  end

  ## Callbacks

  def init({app, root, paths, compilers}) do
    all = Mix.Project.config[:compilers] || Mix.compilers
    compilers = all -- (all -- compilers)
    :ok = :fs.subscribe()
    {:ok, {app, root, paths, compilers}}
  end

  def handle_call(:reload!, from, {app, root, paths, compilers} = state) do
    froms = all_waiting([from])
    reply = mix_compile(Code.ensure_loaded(Mix.Task), app, root, paths, compilers)
    Enum.each(froms, &GenServer.reply(&1, reply))
    {:noreply, state}
  end

  def handle_info({_pid, {:fs, :file_event}, {path, _event}}, socket) do
    IO.inspect {path, _event}
    # if matches_any_pattern?(path, socket.assigns[:patterns]) do
      # asset_type = Path.extname(path) |> String.lstrip(?.)
      # push socket, "assets_change", %{asset_type: asset_type}
    # end

    {:noreply, socket}
  end

  defp matches_any_pattern?(path, patterns) do
    path = to_string(path)

    Enum.any?(patterns, fn pattern ->
      String.match?(path, pattern) and !String.match?(path, ~r/_build/)
    end)
  end

  defp all_waiting(acc) do
    receive do
      {:"$gen_call", from, :reload!} -> all_waiting([from | acc])
    after
      0 -> acc
    end
  end

  defp mix_compile({:error, _reason}, _, _, _, _) do
    Logger.error "If you want to use the code reload plug in production or " <>
                 "inside an escript, add :mix to your list of dependencies or " <>
                 "disable code reloading"
    :ok
  end

  defp mix_compile({:module, Mix.Task}, app, root, paths, compilers) do
    if Mix.Project.umbrella? do
      Mix.Project.in_project(app, root, fn _ -> mix_compile(paths, compilers) end)
    else
      mix_compile(paths, compilers)
    end
  end

  defp mix_compile(paths, compilers) do
    reloadable_paths = Enum.flat_map(paths, &["--elixirc-paths", &1])
    Enum.each compilers, &Mix.Task.reenable("compile.#{&1}")

    suspended_processes = suspend_processes()

    {res, out} =
      proxy_io(fn ->
        try do
          # We call build_structure mostly for Windows
          # so any new assets in priv is copied to the
          # build directory.
          Mix.Project.build_structure
          Enum.each compilers, &Mix.Task.run("compile.#{&1}", reloadable_paths)
        catch
          _, _ -> :error
        end
      end)

    Enum.each(suspended_processes, &:erlang.resume_process/1)

    cond do
      :error in res -> {:error, out}
      :ok in res    -> :ok
      true          -> :noop
    end
  end

  defp proxy_io(fun) do
    original_gl = Process.group_leader
    {:ok, proxy_gl} = Proxy.start()
    Process.group_leader(self(), proxy_gl)

    try do
      res = fun.()
      {List.wrap(res), Proxy.stop(proxy_gl)}
    after
      Process.group_leader(self(), original_gl)
      Process.exit(proxy_gl, :kill)
    end
  end

  defp suspend_processes() do
    # Use internals of `:application.get_application/1` for a 10x speedup.
    # Get pids of all application masters, remove the ones we don't want to suspend.
    application_masters = :ets.match(:ac_tab, {{:application_master, :'$1'}, :'$2'})
    |> Enum.reject(fn [app, _] -> Enum.member?(~w(kernel elixir iex mix code_reloader)a, app) end)
    |> Enum.map(fn [_, pid] -> pid end)

    suspend_processes(application_masters, [])
  end

  # Calls itself recursively until the list of proesses has settled, to catch pids that are spawned
  # while we are busy suspending.
  defp suspend_processes(application_masters, previously_suspended) do
    # Compare a process' group_leader against the list of application masters we want to suspend
    processes = :erlang.processes()
    |> Enum.filter(&Enum.member?(application_masters, Process.info(&1, :group_leader)))
    |> Enum.sort()

    case processes do
      ^previously_suspended -> processes
      _ ->
        Enum.each(processes, &:erlang.suspend_process(&1, [:unless_suspending]))
        suspend_processes(application_masters, processes)
    end
  end
end
