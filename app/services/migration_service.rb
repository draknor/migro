class MigrationService
  include ActionView::Helpers::NumberHelper

  attr_reader :error, :valid_entity_maps

  def initialize(migration_run)
    @run = migration_run
    @source = @run.source_system
    @target = @run.destination_system
    @source_entity = @run.entity_type
    @target_entity = nil
    @error = []
    @error_logs = {}
    @ready = false
    @mapping_values = {}
    @mapping_assoc = {}
    @valid_entity_maps = {
      :highrise => {
        :bullhorn => {
            :company => :client_corporation
        }
      }
    }
    @processing_entity_id = nil
  end

  def run
    @run.preparing!

    error_check unless @ready
    if @error.count > 0
      @run.canceled!
      return
    end

    # the rest of this won't be pretty, but I just want to make it functional
    @run.started_at = Time.now
    @run.running!

    @run.record_list.split("\r\n").each do |entity_id|
      self.send "migrate_#{@source_entity}", entity_id
    end

    if @run.all_records
      page = 0
      max = (@run.max_records == -1) ? 0 : @run.max_records
      begin
        page = page + 1
        entities = @source.retrieve(@source_entity,nil,page)
        max = max + entities.count
        @run.update(max_records: max)
        entities.each do |entity|
          self.send "migrate_#{@source_entity}", entity.id, entity
        end
      end while entities.count > 0
    end

    @run.ended_at = Time.now
    if @error_logs.keys.count > 0
      @run.completed_error!
    else
      @run.completed_success!
    end

  end


  def error_check
    if @valid_entity_maps[@source.integration_type.to_sym].nil?
      @error << 'Invalid source system'
    elsif @valid_entity_maps[@source.integration_type.to_sym][@target.integration_type.to_sym].nil?
      @error << 'Invalid destination system'
    elsif @valid_entity_maps[@source.integration_type.to_sym][@target.integration_type.to_sym][@source_entity.to_sym].nil?
      @error << 'Entity mapping not specified'
    else
      @target_entity = @valid_entity_maps[@source.integration_type.to_sym][@target.integration_type.to_sym][@source_entity.to_sym]
    end

    if @error.count == 0
      @ready = true
    end
  end

  def rescue_after_error
    @run.ended_at = Time.now
    @run.completed_error!
  end

  def migrate_company(entity_id, source_entity = nil)
    puts "[debug] #migrate_company id=#{entity_id}"
    source_entity = @source.get(@source_entity, entity_id) if source_entity.nil?
    if source_entity.nil?
      migration_failed("Could not find entity with ID #{entity_id} in #{@source.system_type}")
      return
    end

    target_entities = @target.search(@target_entity,"customInt1:#{entity_id}")
    if target_entities.count == 0 && !(@run.create_shell? || @run.test_only?)
      migration_failed("No target record found with source ID #{entity_id} and phase is NOT 'create_shell'")
      return
    end

    if target_entities.count > 1
      migration_failed("Multiple target records found with source ID #{entity_id}")
      return
    end

    target_entity = target_entities[0]
    target_entity ||= {}

    @processing_entity_id = entity_id

    options_work = {
        description: '',
        search_attrib: :location,
        search_value: 'Work',
        value_attrib: ''
    }
    options_custom = {
        description: '',
        search_attrib: :subject_field_id,
        search_value: '',
        value_attrib: :value
    }
    data_contact = source_entity.contact_data.attributes
    data_custom = source_entity.subject_datas.map {|n| n.attributes} if source_entity.respond_to?(:subject_datas)

    target_update = {
      name: source_entity.name,
      customInt1: entity_id,
      status: map_value(:status, array_search(data_custom, options_custom.merge({description: 'Status', search_value: 838134}))),
      phone:         format_phone(   array_search(data_contact['phone_numbers'], options_work.merge({description: 'work phone',value_attrib: :number}))),
      address: {
          address1:  format_address( array_search(data_contact['addresses'], options_work.merge({description: 'work address', value_attrib: :street})),1),
          address2:  format_address( array_search(data_contact['addresses'], options_work.merge({description: 'work address', value_attrib: :street})),2),
          city:                      array_search(data_contact['addresses'], options_work.merge({description: 'work city', value_attrib: :city})),
          state:     map_value(:state, array_search(data_contact['addresses'], options_work.merge({description: 'work state', value_attrib: :state})), :address),
          zip:                       array_search(data_contact['addresses'], options_work.merge({description: 'work zip', value_attrib: :zip})),
          countryID: map_value(:countryID, array_search(data_contact['addresses'], options_work.merge({description: 'work country', value_attrib: :country})), :address)

      },
      companyURL:    array_search(data_contact['web_addresses'], options_work.merge({description: 'work URL', value_attrib: :url})),
      customText2:   array_search(data_contact['email_addresses'], options_work.merge({description: 'work email', value_attrib: :address})),
      customText4:   map_value(:customText4, array_search(data_custom, options_custom.merge({description: 'Category', search_value: 846502}))),
      customText8:   map_value(:customText8, array_search(data_custom, options_custom.merge({description: 'Referral Type', search_value: 933697}))),
      customText9:   array_search(data_custom, options_custom.merge({description: 'RFA terms', search_value: 943921})),
      customText10:  map_value(:customText10, array_search(data_custom, options_custom.merge({description: 'SOW', search_value: 943921}))),
      customText11:  map_value(:customText11, array_search(data_custom, options_custom.merge({description: 'PO Reqd', search_value: 929753}))),
      customText12:  array_search(data_contact['web_addresses'], options_work.merge({description: 'other URL', value_attrib: :url, search_value: 'Other'})),

    }
    if @run.add_dependencies?
      target_update.merge({
        customText3:   map_assoc(:customText3, array_search(data_custom, options_custom.merge({description: 'AM', search_value: 838135}))),
        customText5:   map_assoc(:customText5, array_search(data_custom, options_custom.merge({description: 'IC', search_value: 860193}))),
        customText6:   map_assoc(:customText6, array_search(data_custom, options_custom.merge({description: 'IM', search_value: 860194}))),
        customText7:   map_assoc(:customText7, array_search(data_custom, options_custom.merge({description: 'Referral Name', search_value: 933698}))),
      })
    end


    # ok, prepare to create / update here
    msg = ''
    target_entity_id = target_entity[:id]

    if @run.test_only?
      msg = "(test only)"
    else
      if target_entity.empty?
        result = @target.create(@target_entity, target_update)
        target_entity_id = result[:changedEntityId] if result.class == Hashie::Mash && !result[:changedEntityId].nil?
      else
        result = @target.update(@target_entity, target_entity[:id], target_update)
      end

      if result.class == ServiceError
        msg = result.message
      elsif result[:errorMessage]
        result[:errors].each {|n| log_error("API Error: #{n[:detailMessage]}") }
        msg = "Target save failed: " + (result[:errors].map {|n| n[:detailMessage]}).join('; ')
      elsif result[:changeType]
        msg = "Target record #{result[:changeType].downcase}'d"
      else
        msg = "Unknown result"
      end
    end

    log_migration({source_entity: source_entity, target_entity_id: target_entity_id, target_before: target_entity, target_after: target_update, message: msg})
    @run.increment_record!
    @processing_entity_id = nil

  end

  def migration_failed(msg)
    log_error(msg)
    @run.ended_at = Time.now
    @run.completed_error!
  end

  def log_error(msg)
    log = @error_logs[msg]
    if log.nil?
      log = @run.migration_logs.create(log_type: MigrationLog.log_types[:error], message: msg, id_list: @processing_entity_id)
      @error_logs[msg] = log
    else
      log.add_id!(@processing_entity_id)
    end
  end

  # source_entity, target_entity_id, target_before, target_after, message
  def log_migration(v={})
    @run.migration_logs.create(log_type: MigrationLog.log_types[:mapped], source_id: v[:source_entity].id, source_before: v[:source_entity].to_json, target_id: v[:target_entity_id], target_before: v[:target_before].to_json, target_after: v[:target_after].to_json, message: v[:message])
  end

  def format_phone(val)
    val.nil? ? nil : number_to_phone(val.tr('()-.– ',''))
  end

  def format_address(val,line)
    val.nil? || val.empty? ? nil : val.split("\n")[line-1]
  end

  def map_value(field,val,parent_field=nil)
    # puts "[debug] map_value: field = #{field}, value = #{val}"
    cache_values(field, parent_field) if @mapping_values[field].nil?

    transform_val = MappingService.transform(@target.integration_type,field,val)

    return '' if val.blank?

    transform_val.downcase!

    log_error("No mapped value found for '#{val}' #{val == transform_val ? '' : "(transformed to #{transform_val})"} in #{field}") if @mapping_values[field][transform_val].blank?

    @mapping_values[field][transform_val]
  end


  def cache_values(field, parent_field)
    # puts "[debug] cache_values: field = #{field}"
    meta_fields = @target.get_meta(@target_entity)
    log_error("No metadata for field meta_field '#{field}'") if meta_fields.empty?

    if meta_fields[0].class == ServiceError
      log_error("Error retrieving field '#{field} metadata: #{meta_fields[0].message}")
      meta_fields = []
    end

    return nil if meta_fields.empty?

    if parent_field.nil?
      fields_array = meta_fields.fields
    else
      fields_array = array_search(meta_fields.fields,{description: "Getting nested fields for #{parent_field}", search_attrib: :name, search_value: parent_field, value_attrib: :fields})
    end

    options_array = array_search(fields_array,{description: "Getting options for #{field}", search_attrib: :name, search_value: field, value_attrib: :options})
    # puts "[debug] got option_array=#{options_array}"
    if options_array.nil? || options_array.count == 0
      option_type = array_search(fields_array,{description: "Getting options type for #{field}", search_attrib: :name, search_value: field, value_attrib: :optionsType})
      # puts "[debug] got option_type=#{option_type} - going to get option_array now"
      options_array = @target.get_option(option_type) unless option_type.blank?
      # puts "[debug] got option_array=#{options_array}"
      if !options_array.nil? && options_array[0].class == ServiceError
        log_error("Error retrieving field '#{field} options: #{options_array[0].message}")
        options_array = []
      end
    end

    options_hash = {}
    options_array ||= []
    options_array.map {|n| options_hash[n[:label].downcase] = n[:value]}
    log_error("No options found for #{field} #{parent_field.nil? ? '' : "under #{parent_field}"}") if options_hash.empty?

    @mapping_values[field] = options_hash
  end

  def map_assoc(field, val)
    return '' if val.nil? || val.empty?
    cache_assoc(field, val) if @mapping_values[field][val].nil?

    @mapping_assoc[field][val]
  end

  def cache_assoc(field, val)
    # TODO fill this out:
    # 1. Identify what fields map to what entity types for Bullhorn
    # 2. Figure out how to search for entities of said type by "val"
    # 3. Store @mapping_assoc[field][val] = entity_id
  end

  # options should contain :search_attrib, :search_value, :value_attrib, :id, :description
  def array_search(array,options = {})
    # puts "[debug] array_search: options = #{options}"
    value = nil
    array ||= []
    array.each do |obj|
      hash = obj.class.to_s.include?('Highrise') ? obj.attributes : obj
      if hash[options[:search_attrib]].to_s == options[:search_value].to_s
        if value.nil?
          value = hash[options[:value_attrib]]
        else
          log_error "Multiple values found for #{options[:description]} - no value migrated"
          return nil
        end
      end
    end
    value
  end



end