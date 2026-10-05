defmodule Demo.Tracker do
  @moduledoc """
  The issue tracker: organizations (the tenant), users, projects, tasks,
  comments and labels.
  """
  use Ash.Domain, otp_app: :demo

  resources do
    resource Demo.Tracker.Organization
    resource Demo.Tracker.User
    resource Demo.Tracker.Project
    resource Demo.Tracker.Task
    resource Demo.Tracker.Comment
    resource Demo.Tracker.Label
    resource Demo.Tracker.TaskLabel
  end
end
