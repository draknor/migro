class DropEntities < ActiveRecord::Migration
  def up
    drop_table :entities
  end

  def down
    create_table :entities do |t|
      t.string :name
      t.references :systems

      t.timestamps
    end

  end
end
