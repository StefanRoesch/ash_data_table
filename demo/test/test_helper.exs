# A LiveView test waits this long for async work, a patch or a redirect. A
# single statement can stall for a few seconds when the whole suite runs side
# by side (seen: up to 3.6 s), so the limit is far above that. A test that
# passes never waits it out.
ExUnit.start(assert_receive_timeout: 10_000)
Ecto.Adapters.SQL.Sandbox.mode(Demo.Repo, :manual)
