defmodule Oban.Web.MyXQLRepo.Migrations.CreateObanJobLogs do
  use Ecto.Migration

  def change do
    create table(:oban_job_logs) do
      add :job_id, :integer, null: false
      add :level, :text, null: false
      add :source, :text, null: false
      add :message, :text, null: false
      add :logger_metadata, :map, null: false, default: %{}
      add :logged_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:oban_job_logs, [:job_id, :logged_at])
    create index(:oban_job_logs, [:job_id, :id])
  end
end
