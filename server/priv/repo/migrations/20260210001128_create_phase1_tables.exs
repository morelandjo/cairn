defmodule Cairn.Repo.Migrations.CreatePhase1Tables do
  use Ecto.Migration

  def change do
    execute "CREATE EXTENSION IF NOT EXISTS citext", ""

    create table(:users, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :username, :citext, null: false
      add :display_name, :string, size: 64
      add :password_hash, :string, null: false
      add :identity_public_key, :binary
      add :signed_prekey, :binary
      add :signed_prekey_signature, :binary
      add :totp_secret, :binary

      timestamps()
    end

    create unique_index(:users, [:username])

    create table(:roles, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :name, :string, null: false
      add :permissions, :map, default: %{}, null: false
      add :priority, :integer, default: 0, null: false
      add :color, :string

      timestamps()
    end

    create unique_index(:roles, [:name])

    create table(:channels, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :name, :string, size: 100, null: false
      add :type, :string, size: 16, default: "public", null: false
      add :description, :text
      add :topic, :string, size: 512

      timestamps()
    end

    create table(:channel_members, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :channel_id, references(:channels, type: :uuid, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :role, :string, size: 16, default: "member", null: false

      timestamps()
    end

    create unique_index(:channel_members, [:channel_id, :user_id])
    create index(:channel_members, [:user_id])

    create table(:messages, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :channel_id, references(:channels, type: :uuid, on_delete: :delete_all), null: false
      add :author_id, references(:users, type: :uuid, on_delete: :nilify_all)
      add :content, :text
      add :encrypted_content, :binary
      add :nonce, :binary
      add :edited_at, :utc_datetime
      add :deleted_at, :utc_datetime

      timestamps()
    end

    create index(:messages, [:channel_id, :inserted_at])
    create index(:messages, [:author_id])

    create table(:recovery_codes, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :code_hash, :string, null: false
      add :used_at, :utc_datetime

      timestamps()
    end

    create index(:recovery_codes, [:user_id])

    create table(:invite_links, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :code, :string, size: 8, null: false
      add :creator_id, references(:users, type: :uuid, on_delete: :nilify_all)
      add :channel_id, references(:channels, type: :uuid, on_delete: :delete_all)
      add :max_uses, :integer
      add :uses, :integer, default: 0, null: false
      add :expires_at, :utc_datetime

      timestamps()
    end

    create unique_index(:invite_links, [:code])

    create table(:refresh_tokens, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :token_hash, :string, null: false
      add :expires_at, :utc_datetime, null: false
      add :revoked_at, :utc_datetime

      timestamps()
    end

    create unique_index(:refresh_tokens, [:token_hash])
    create index(:refresh_tokens, [:user_id])

    create table(:one_time_prekeys, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :key_id, :integer, null: false
      add :public_key, :binary, null: false
      add :consumed, :boolean, default: false, null: false

      timestamps()
    end

    create index(:one_time_prekeys, [:user_id])
    create unique_index(:one_time_prekeys, [:user_id, :key_id])

    create table(:files, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :uploader_id, references(:users, type: :uuid, on_delete: :nilify_all)
      add :storage_key, :string, null: false
      add :original_name, :string, null: false
      add :content_type, :string, null: false
      add :size_bytes, :bigint, null: false
      add :thumbnail_key, :string

      timestamps()
    end

    create index(:files, [:uploader_id])
  end
end
