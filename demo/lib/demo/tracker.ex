defmodule Demo.Tracker do
  @moduledoc """
  The issue tracker: organizations (the tenant), users, projects, tasks,
  comments and labels.
  """
  use Ash.Domain, otp_app: :demo, extensions: [AshTable.Domain]

  # How the tables of these resources authorize, and under which socket
  # assigns a mounted table finds who is asking. These are the defaults,
  # written out; `DemoWeb.Actor` sets the two assigns.
  table do
    authorize? true
    actor_assign :current_user
    tenant_assign :current_tenant
  end

  resources do
    resource Demo.Tracker.Organization
    resource Demo.Tracker.User
    resource Demo.Tracker.Project
    resource Demo.Tracker.Task
    resource Demo.Tracker.Deadline
    resource Demo.Tracker.Comment
    resource Demo.Tracker.Label
    resource Demo.Tracker.TaskLabel
  end
end
