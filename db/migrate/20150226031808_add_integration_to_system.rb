class AddIntegrationToSystem < ActiveRecord::Migration
  def change
    add_column :systems, :integration_type, :integer
  end
end
