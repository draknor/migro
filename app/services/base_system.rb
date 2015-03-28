class BaseSystem

  # This is the base template to use for implementing any "system" API
  # Subclass this object and build out all the following methods

  @@entities = []

  def self.entities
    @@entities
  end

  def self.account_info

  end

  def self.search(entity, query)

  end
end