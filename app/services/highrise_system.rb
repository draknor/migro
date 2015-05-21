class HighriseSystem < BaseSystem

  @entities = [
      :account, :comment, :company, :deal, :deal_category, :email, :group, :case, :membership,
      :note, :party, :person, :recording, :subject, :tag, :task, :task_category, :user
  ]

  def self.max_per_page
    500  # HR returns this many results per page
  end


  def self.account_info
    # Hashie::Mash.new JSON.parse Highrise::Account.me.to_json
    JSON.parse Highrise::Account.me.to_json
  end

  def self.search(entity, query)
    puts "[debug] HighriseSystem#search: #{entity}, #{query}"
    if query == query.to_i.to_s  # assume query = entity_id if query is an integer
      return [get(entity,query)]
    end
    mod = entity.to_s.camelize
    results = Highrise.const_get(mod).search(term: query)
    return [] if results.nil?
    results
  end

  def self.retrieve(entity,timestamp, page)
    puts "[debug] HighriseSystem#retrieve: #{entity}, #{timestamp}, #{page}"
    mod = entity.to_s.camelize
    offset = page > 1 ? (page - 1) * self.max_per_page : 0
    params = {}
    params[:since] = timestamp.utc.strftime('%Y%m%d%H%M%S') unless timestamp.nil?
    params[:n] = offset if offset>0

    results = Highrise.const_get(mod).find(:all, params: params )
    return [] if results.nil?
    results
  end

  def self.get(entity, entity_id)
    puts "[debug] HighriseSystem#get: #{entity}, #{entity_id}"
    mod = entity.to_s.camelize
    result = Highrise.const_get(mod).find(entity_id)
    result
  end

  def self.query(entity, where)

  end



end