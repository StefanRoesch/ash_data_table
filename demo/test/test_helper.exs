# A LiveView test waits this long for async work, a patch or a redirect. The
# default of 100 ms is too short for a busy machine.
ExUnit.start(assert_receive_timeout: 2_000)
Ecto.Adapters.SQL.Sandbox.mode(Demo.Repo, :manual)
