class BaseSystem

  # This is the base template to use for implementing any "system" API
  # Subclass this object and build out all the following methods

  @@entities = []

  def self.entities
    @@entities
  end

  def self.account_info
    # Should return JSON object
  end

  def self.search(entity, query)

  end

  def self.retrieve(entity, timestamp, page)

  end

  def self.max_per_page

  end

  end