class BullhornSystem < BaseSystem

  @conn_options = {

  }

  @client ||= Bullhorn::Rest::Client.new(
      username: Rails.application.secrets[:bullhorn][:username],
      password: Rails.application.secrets[:bullhorn][:password],
      client_id: Rails.application.secrets[:bullhorn][:client_id],
      client_secret: Rails.application.secrets[:bullhorn][:client_secret],
      auth_host: Rails.application.secrets[:bullhorn][:auth_host],
      rest_host: Rails.application.secrets[:bullhorn][:rest_host]
  )

  @entities = [
      :appointment, :appointment_attendee, :business_sector, :candidate, :candidate_certification,
      :candidate_education, :candidate_reference, :candidate_work_history, :category, :client_contact,
      :client_corporation, :corporate_user, :corporation_department, :country, :custom_action, :job_order,
      :job_submission, :note, :note_entity, :placement, :placement_change_request, :placement_commission,
      :sendout, :skill, :specialty, :state, :task, :tearsheet, :tearsheet_recipient, :time_unit

  ]

  @cache_meta = {}
  @cache_option = {}

  # really just for debugging purposes
  def self.client_obj
    @client
  end

  def self.account_info
    # @client.settings
    JSON.parse @client.settings.data.to_json
  end

  def self.search(entity, query)
    return [get_meta(entity)] if query == '-1'
    if query == query.to_i.to_s  # assume query = entity_id if query is an integer
      return [get(entity,query)]
    end
    case entity.to_s.underscore.pluralize
      when 'candidates'
        resp = @client.send "search_#{entity.to_s.underscore.pluralize}", { query: query }
      else
        resp = @client.send "query_#{entity.to_s.underscore.pluralize}", { where: query }
    end

    return resp.data unless resp.data.nil?
    []
  end

  def self.retrieve(entity,timestamp, page)
    resp = @client.send entity.to_s.pluralize
    return resp.data unless resp.data.nil?
    []
  end

  def self.get(entity, entity_id)
    resp = @client.send entity.to_s, entity_id
    return resp.data unless resp.data.nil?
  end

  def self.query(entity, query)
    resp = @client.send "query_#{entity.to_s.underscore.pluralize}", { where: query }

    return resp.data unless resp.data.nil?
    []
  end

  def self.get_meta(entity)
    return @cache_meta[entity] unless @cache_meta[entity].nil?

    resp = @client.send entity.to_s, 1,{meta: 'full'}
    if resp.meta.nil?  # record with ID 1 must not exist - find another record
      find_resp = @client.send "query_#{entity.to_s.pluralize}",{count: 1, where: 'id IS NOT NULL',fields:'id'}
      resp = @client.send entity.to_s, find_resp.data[0][:id], {meta: 'full'} unless find_resp.data.nil?
    end

    if resp.meta.nil?  # record with ID 1 must not exist && query didn't work, try searching
      find_resp = @client.send "search_#{entity.to_s.pluralize}", {query: 'id:[0 TO 9]', count:1, fields: 'id'}
      resp = @client.send entity.to_s, find_resp.data[0][:id], {meta: 'full'} unless find_resp.data.nil? || find_resp.data.count == 0
    end
    @cache_meta[entity] = resp.meta
    resp.meta
  end

  def self.get_option(option_type, value='*')
    return @cache_option[option_type] unless @cache_option[option_type].nil? || value != '*'

    start = 0
    count = 300
    data = []

    begin
      resp = @client.option(option_type, value, {start: start, count: count})
      data.concat(resp.data) unless resp.data.nil?
      start = start+count
    end until resp.data.nil? || resp.data.empty?
    @cache_option[option_type] = data if value == '*'
    data

  end

  def self.create(entity,attributes)
    @client.send "create_#{entity}", attributes
  end

  def self.update(entity,id,attributes)
    @client.send "update_#{entity}", id, attributes
  end

  def self.add_association(entity,id,assoc_entity,values = [])
    curr_resp = @client.send "get_#{entity}_associations", id, assoc_entity, {fields: id}
    curr_vals = curr_resp[:data].map {|n| n[:id]}

    if (values - curr_vals).count < 1
      resp = Hashie::Mash.new
      resp.message = "All #{assoc_entity} values currently set - no updates made"
    else
      resp = @client.send "add_#{entity}_association", id, assoc_entity, (values - curr_vals)
    end

    resp
  end
end