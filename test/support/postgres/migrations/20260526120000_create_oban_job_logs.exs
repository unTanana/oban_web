defmodule Oban.Web.Repo.Migrations.CreateObanJobLogs do
  use Ecto.Migration

  def up, do: Oban.Web.JobLogs.Migration.up()
  def down, do: Oban.Web.JobLogs.Migration.down()
end
