class DropFields < ActiveRecord::Migration
  def up
    drop_table :fields
  end

  def down
    create_table :fields do |t|
      t.string :name
      t.references :entities

      t.timestamps
    end

  end
end
