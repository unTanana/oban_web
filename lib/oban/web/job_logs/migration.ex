defmodule Oban.Web.JobLogs.Migration do
  @moduledoc """
  Migrations for the `oban_job_logs` table used by `Oban.Web.JobLogs`.

  Generate a migration in your application and delegate to this module:

      def up, do: Oban.Web.JobLogs.Migration.up()
      def down, do: Oban.Web.JobLogs.Migration.down()
  """

  use Ecto.Migration

  def up(opts \\ []) when is_list(opts) do
    create_if_not_exists table(:oban_job_logs, table_opts(opts)) do
      add :job_id, :integer, null: false
      add :level, :text, null: false
      add :source, :text, null: false
      add :message, :text, null: false
      add :logger_metadata, :map, null: false, default: %{}
      add :logged_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime)
    end

    create_if_not_exists index(:oban_job_logs, [:job_id, :logged_at], index_opts(opts))
    create_if_not_exists index(:oban_job_logs, [:job_id, :id], index_opts(opts))
  end

  def down(opts \\ []) when is_list(opts) do
    drop_if_exists table(:oban_job_logs, table_opts(opts))
  end

  defp table_opts(opts), do: Keyword.take(opts, [:prefix])
  defp index_opts(opts), do: Keyword.take(opts, [:prefix])
end
