class BaseSystem

  # This is the base template to use for implementing any "system" API
  # Subclass this object and build out all the following methods

  @entities = []

  def self.entities
    @entities
  end

  def self.account_info
    # Should return JSON object
  end

  def self.search(entity, query)
  end

  def self.retrieve(entity, timestamp, page)
  end

  def self.get(entity, entity_id)
  end

  def self.query(entity, where)
  end

  def self.get_meta(entity)
  end

  def self.max_per_page
  end

  def self.get_option(option_type)
  end

  def self.create(entity,attributes)
  end

  def self.update(entity,id,attributes)
  end
end