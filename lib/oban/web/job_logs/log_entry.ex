defmodule Oban.Web.JobLogs.LogEntry do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @levels [:debug, :info, :notice, :warning, :error, :critical, :alert, :emergency]
  @sources [:logger, :lifecycle]

  schema "oban_job_logs" do
    field :job_id, :integer
    field :level, Ecto.Enum, values: @levels
    field :source, Ecto.Enum, values: @sources
    field :message, :string
    field :logger_metadata, :map, default: %{}
    field :logged_at, :utc_datetime_usec

    timestamps(type: :utc_datetime)
  end

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:job_id, :level, :source, :message, :logger_metadata, :logged_at])
    |> put_default_logged_at()
    |> validate_required([:job_id, :level, :source, :message, :logger_metadata, :logged_at])
    |> validate_number(:job_id, greater_than: 0)
  end

  defp put_default_logged_at(changeset) do
    case get_field(changeset, :logged_at) do
      nil -> put_change(changeset, :logged_at, DateTime.utc_now(:microsecond))
      _logged_at -> changeset
    end
  end
end
