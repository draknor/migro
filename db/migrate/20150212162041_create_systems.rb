class CreateSystems < ActiveRecord::Migration
  def change
    create_table :systems do |t|
      t.string :name
      t.string :ref_url

      t.timestamps null: false
    end
  end
end
