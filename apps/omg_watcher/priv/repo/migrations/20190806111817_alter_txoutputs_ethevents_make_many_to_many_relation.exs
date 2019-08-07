
defmodule OMG.Watcher.DB.Repo.Migrations.AlterTxOutputsTableAddRootchainTxnHashDepositAndExitColumns do
  use Ecto.Migration

  # non-backward compatible migration, thus cannot use `change/0`

  def up do
    drop constraint(:txoutputs, "txoutputs_creating_deposit_fkey")
    drop constraint(:txoutputs, "txoutputs_spending_exit_fkey")
    drop constraint(:ethevents, "ethevents_pkey")

    flush()

    alter table(:ethevents) do
      remove(:hash)
      remove(:blknum)
      remove(:txindex)

      add(:rootchain_txhash, :binary, primary_key: true)

      timestamps([type: :utc_datetime])
    end

    # how to do this in ecto correctly? do it manually
    execute("ALTER TABLE ethevents ALTER COLUMN inserted_at SET DEFAULT (now() at time zone 'utc');");
    execute("ALTER TABLE ethevents ALTER COLUMN updated_at SET DEFAULT (now() at time zone 'utc');");


    alter table(:txoutputs) do
      add(:childchain_utxohash, :binary)
    end

    create(
      unique_index(:txoutputs, :childchain_utxohash, name: :childchain_utxohash_unique_index)


    flush()

    # backfill childchain_utxohash with values from either creating_deposit or spending_exit
    execute """
      UPDATE txoutputs as t
        SET childchain_utxohash =
          (SELECT
             CASE WHEN creating_deposit IS NULL THEN spending_exit
                  WHEN spending_exit IS NULL THEN creating_deposit
                  ELSE creating_deposit || spending_exit
             END AS txhash
           FROM txoutputs as t_inner
           WHERE t.creating_deposit = t_inner.creating_deposit OR t.spending_exit = t_inner.spending_exit);
    """

    # delete all entries from ethevents table as this table is currently unused for all practical purposes.
    # when getting utxos we filter on txoutputs.creating_deposit is nil and txoutputs.spending is nil and
    # never query/join with the ethevents table
    execute("DELETE FROM ethevents;")

    alter table(:txoutputs) do
      remove(:creating_deposit)
      remove(:spending_exit)

      timestamps([type: :utc_datetime])
    end

    # how to do this in ecto correctly? do it manually
    execute("ALTER TABLE txoutputs ALTER COLUMN inserted_at SET DEFAULT (now() at time zone 'utc');");
    execute("ALTER TABLE txoutputs ALTER COLUMN updated_at SET DEFAULT (now() at time zone 'utc');");


    create table(:ethevents_txoutputs, primary_key: false) do
      add(:rootchain_txhash, references(:ethevents, column: :rootchain_txhash, type: :binary, on_delete: :restrict), primary_key: true)
      add(:childchain_utxohash, references(:txoutputs, column: :childchain_utxohash, type: :binary, on_delete: :restrict), primary_key: true)

      timestamps([type: :utc_datetime])
    end

    # how to do this in ecto correctly? do it manually
    execute("ALTER TABLE ethevents_txoutputs ALTER COLUMN inserted_at SET DEFAULT (now() at time zone 'utc');");
    execute("ALTER TABLE ethevents_txoutputs ALTER COLUMN updated_at SET DEFAULT (now() at time zone 'utc');");


    create(index(:ethevents_txoutputs, :rootchain_txhash))
    create(index(:ethevents_txoutputs, :childchain_utxohash))
  end

  def down do
    # non-backward compatible migration, thus cannot use `change/0`
    # no-op
  end
end
