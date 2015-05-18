class MigrationService
  include ActionView::Helpers::NumberHelper

  attr_reader :error, :valid_entity_maps, :mapping_values
  attr_accessor :target_entity_type, :current

  def initialize(migration_run)
    @run = migration_run
    @source = @run.source_system
    @target = @run.destination_system
    @source_entity_type = @run.entity_type
    @target_entity_type = nil
    @error = []
    @error_logs = {}
    @ready = false
    @mapping_values = {}
    @mapping_assoc = {}
    @valid_entity_maps = {
      :highrise => {
        :bullhorn => {
            :company => :client_corporation,
            :person => [:candidate, :client_contact]
        }
      }
    }
    @current = {}

  end

  def options_custom
    {
        search_attrib: :subject_field_label,
        search_value: '',
        value_attrib: :value
    }
  end

  def options_work
    {
        search_attrib: :location,
        search_value: 'Work',
        value_attrib: ''
    }
  end

  def options_home
    {
        search_attrib: :location,
        search_value: 'Home',
        value_attrib: ''
    }
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
      @current = { source_id: entity_id }
      entity = @source.get(@source_entity_type, @current[:source_id])
      if entity.nil?
        migration_failed("Could not find entity with ID #{@current[:source_id]} in #{@source.system_type}")
      else
        @current[:source_entity] = entity
        self.send "migrate_#{@source_entity_type}"
      end
    end
    @current = {}

    if @run.all_records
      page = 0
      max = (@run.max_records == -1) ? 0 : @run.max_records
      begin
        page = page + 1
        entities = @source.retrieve(@source_entity_type,nil,page)
        max = max + entities.count
        @run.update(max_records: max)
        entities.each do |entity|
          @current = { source_id: entity.id, source_entity: entity }
          self.send "migrate_#{@source_entity_type}"
        end
        @current = {}
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
    elsif @valid_entity_maps[@source.integration_type.to_sym][@target.integration_type.to_sym][@source_entity_type.to_sym].nil?
      @error << 'Entity mapping not specified'
    else
      @target_entity_type = @valid_entity_maps[@source.integration_type.to_sym][@target.integration_type.to_sym][@source_entity_type.to_sym]
    end

    if @error.count == 0
      @ready = true
    end
  end

  def rescue_after_error
    @run.ended_at = Time.now
    @run.completed_error!
  end

  def migrate_person
    puts "[debug] #migrate_person id=#{@current[:source_id]}"

    source_entity = @current[:source_entity]
    data_custom = source_entity.subject_datas.map {|n| n.attributes} #if source_entity.respond_to?(:subject_datas)

    target_type = array_search(data_custom, options_custom.merge({search_value: 'zzz Migration Flag- Contact vs Candidate'}))
    if target_type.blank?
      migration_failed("'Migration Flag - Contact vs Candidate' field not set")
      return
    end
    target_type.downcase!

    if (target_type == 'contact')
      @target_entity_type = :client_contact
      migrate_person_to_contact
    elsif (target_type == 'candidate')
      @target_entity_type = :candidate
      migrate_person_to_candidate
    else
      migration_failed("'Migration Flag - Contact vs Candidate' value not recognized: '#{target_type}'")
    end

  end

  def migrate_person_to_contact
    puts "[debug] #migrate_person_to_contact id=#{@current[:source_id]}"
    get_target_entity
    return if @current[:target_entity].nil?  # failed

    source_entity = @current[:source_entity]
    target_update = {}
    data_contact = source_entity.contact_data.attributes
    data_custom = source_entity.respond_to?(:subject_datas) ? source_entity.subject_datas.map {|n| n.attributes} : []

    if @run.test_only? || @run.create_shell?
      # dateAdded: format_timestamp(source_entity.created_at),
      target_update.merge!({
         firstName: source_entity.first_name,
         lastName: source_entity.last_name,
         name: source_entity.first_name + ' ' + source_entity.last_name,
         customInt1: @current[:source_id],
         occupation: format_str(source_entity.title,50),
         mobile: format_phone(array_search(data_contact['phone_numbers'], options_work.merge({value_attrib: :number, search_value: 'Mobile'}))),
         workPhone: format_phone(array_search(data_contact['phone_numbers'], options_work.merge({value_attrib: :number}))),
         email: array_search(data_contact['email_addresses'], options_work.merge({value_attrib: :address})),
         email2: array_search(data_contact['email_addresses'], options_home.merge({value_attrib: :address})),
         address: {
             address1:  format_address( array_search(data_contact['addresses'], options_work.merge({value_attrib: :street})),1),
             address2:  format_address( array_search(data_contact['addresses'], options_work.merge({value_attrib: :street})),2),
             city:                      array_search(data_contact['addresses'], options_work.merge({value_attrib: :city})),
             state:     map_value(:state, array_search(data_contact['addresses'], options_work.merge({value_attrib: :state})), :address),
             zip:                       array_search(data_contact['addresses'], options_work.merge({value_attrib: :zip})),
             countryID: map_value(:countryID, array_search(data_contact['addresses'], options_work.merge({value_attrib: :country})), :address)
         },
         clientCorporation: map_assoc(:clientCorporation, source_entity.company_id)
      })

      update_target(target_update)
      @run.increment_record!

    end

  end

  def migrate_person_to_candidate
    puts "[debug] #migrate_person_to_candidate id=#{@current[:source_id]}"
    get_target_entity
    return if @current[:target_entity].nil?  # failed

    source_entity = @current[:source_entity]
    target_update = {}
    target_update_assoc = {}
    mapped_apps = {}
    mapped_roles = {}
    data_contact = source_entity.contact_data.attributes
    data_custom = source_entity.respond_to?(:subject_datas) ? source_entity.subject_datas.map {|n| n.attributes} : []

    if @run.test_only? || @run.create_shell?
      # dateAdded: format_timestamp(source_entity.created_at),
      target_update.merge!({
          firstName: source_entity.first_name,
          lastName: source_entity.last_name,
          name: source_entity.first_name + ' ' + source_entity.last_name,
          customInt1: @current[:source_id],
          customText1: map_value(:customText1, array_search(data_custom, options_custom.merge({search_value: 'Rec: Open to BlueTree Roles?'}))),
          customText4: map_value(:customText4, array_search(data_custom, options_custom.merge({search_value: 'Rec: BlueTree Quality'}))),
          comments: format_comments(array_search(data_custom,options_custom.merge({search_value: 'Rec: BlueTree Quality Comments'}))),
          occupation: format_str(source_entity.title,50),
          email: array_search(data_contact['email_addresses'], options_work.merge({value_attrib: :address})),
          email2: array_search(data_contact['email_addresses'], options_home.merge({value_attrib: :address})),
          mobile: format_phone(array_search(data_contact['phone_numbers'], options_work.merge({value_attrib: :number, search_value: 'Mobile'}))),
          workPhone: format_phone(array_search(data_contact['phone_numbers'], options_work.merge({value_attrib: :number}))),
          address: {
              address1:  format_address( array_search(data_contact['addresses'], options_home.merge({value_attrib: :street})),1),
              address2:  format_address( array_search(data_contact['addresses'], options_home.merge({value_attrib: :street})),2),
              city:                      array_search(data_contact['addresses'], options_home.merge({value_attrib: :city})),
              state:     map_value(:state, array_search(data_contact['addresses'], options_home.merge({value_attrib: :state})), :address),
              zip:                       array_search(data_contact['addresses'], options_home.merge({value_attrib: :zip})),
              countryID: map_value(:countryID, array_search(data_contact['addresses'], options_home.merge({value_attrib: :country})), :address)
          },
          employmentPreference: map_value(:employmentPreference, array_search(data_custom,options_custom.merge({search_value: 'Rec: FTE preferences'}))),
          dateAvailable: array_search(data_custom,options_custom.merge({search_value: 'Rec: Available After'})),
          travelLimit: format_travel_limit(array_search(data_custom,options_custom.merge({search_value: 'Rec: Max Travel %'}))),
          customText3: map_value(:customText3, array_search(data_custom,options_custom.merge({search_value: 'Rec: Interested in Canopy?'}))),
          customTextBlock2: array_search(data_custom,options_custom.merge({search_value: 'Rec: Recruitment/ Placement notes'}))
      })
      mapped_apps = MappingService.map_highrise_apps(data_custom)
      target_update.merge!({customText7: map_value_array(:customText7,mapped_apps[:p])}) unless mapped_apps[:p].nil? || mapped_apps[:p].count==0
      target_update.merge!({customText6: map_value_array(:customText6,mapped_apps[:t])}) unless mapped_apps[:t].nil? || mapped_apps[:t].count==0
      target_update_assoc.merge!({primarySkills: map_value_array(:primarySkills,mapped_apps[:q])}) unless mapped_apps[:q].nil? || mapped_apps[:q].count==0
      target_update.merge!({customText12: map_value_array(:customText12,mapped_apps[:c])}) unless mapped_apps[:c].nil? || mapped_apps[:c].count==0
      mapped_apps[:unknown].each { |app| log_error("Unknown ZCONAPP value: '#{app}'") } unless mapped_apps[:unknown].nil?

      mapped_roles = MappingService.map_highrise_roles(data_custom)
      target_update.merge!({customText8:  map_value_array(:customText8, mapped_roles[:p])}) unless mapped_roles[:p].nil? || mapped_roles[:p].count==0
      target_update.merge!({customText13: map_value_array(:customText13,mapped_roles[:p])}) unless mapped_roles[:s].nil? || mapped_roles[:s].count==0
      q_roles = mapped_roles[:q].nil? ? [] : mapped_roles[:q]
      e_roles = mapped_roles[:e].nil? ? [] : mapped_roles[:e]
      target_update_assoc.merge!({specialties: map_value_array(:specialties,q_roles + e_roles)}) unless (q_roles + e_roles).count==0
      mapped_roles[:unknown].each { |role| log_error("Unknown ZCONROLE value: '#{role}'") } unless mapped_roles[:unknown].nil?
    end

    if @run.add_dependencies?
      target_update.merge!({
          recruiterUserID: map_assoc(:recruiterUserID, array_search(data_custom, options_custom.merge({search_value: 'HR: Consultant Advocate / Internal Manager'}))),
          companyName: map_assoc(:companyName, source_entity.company_name),
          referredByUserID: map_assoc(:referredByUserID, array_search(data_custom, options_custom.merge({search_value: 'Rec: Referred by'}))),
          referredBy: ''
      })
    end


    # Need to map certs/roles => add_candidate_association
    update_target(target_update)
    update_target_assoc(target_update_assoc) unless target_update_assoc.empty?
    @run.increment_record!


  end


  def migrate_company
    puts "[debug] #migrate_company id=#{@current[:source_id]}"

    get_target_entity
    return if @current[:target_entity].nil?  # failed
    source_entity = @current[:source_entity]

    target_update = {}
    data_contact = source_entity.contact_data.attributes
    data_custom = source_entity.respond_to?(:subject_datas) ? source_entity.subject_datas.map {|n| n.attributes} : []

    if @run.test_only? || @run.create_shell?
      target_update.merge!({
        name: source_entity.name,
        customInt1: @current[:source_id],
        status: map_value(:status, array_search(data_custom, options_custom.merge({search_value: 'AM: Status'}))),
        phone:         format_phone(   array_search(data_contact['phone_numbers'], options_work.merge({value_attrib: :number}))),
        address: {
            address1:  format_address( array_search(data_contact['addresses'], options_work.merge({value_attrib: :street})),1),
            address2:  format_address( array_search(data_contact['addresses'], options_work.merge({value_attrib: :street})),2),
            city:                      array_search(data_contact['addresses'], options_work.merge({value_attrib: :city})),
            state:     map_value(:state, array_search(data_contact['addresses'], options_work.merge({value_attrib: :state})), :address),
            zip:                       array_search(data_contact['addresses'], options_work.merge({value_attrib: :zip})),
            countryID: map_value(:countryID, array_search(data_contact['addresses'], options_work.merge({value_attrib: :country})), :address)

        },
        companyURL:    array_search(data_contact['web_addresses'], options_work.merge({value_attrib: :url})),
        customText2:   array_search(data_contact['email_addresses'], options_work.merge({value_attrib: :address})),
        customText4:   map_value(:customText4, array_search(data_custom, options_custom.merge({search_value: 'AM: Category'}))),
        customText8:   map_value(:customText8, array_search(data_custom, options_custom.merge({search_value: 'AM: Referral Source Type'}))),
        customText9:   array_search(data_custom, options_custom.merge({search_value: 'AM: RFA Terms'})),
        customText10:  map_value(:customText10, array_search(data_custom, options_custom.merge({search_value: "AM: SOW (BlueTree's or Client's)"}))),
        customText11:  map_value(:customText11, array_search(data_custom, options_custom.merge({search_value: "HR: HCO requires purchase order ID?"}))),
        customText12:  array_search(data_contact['web_addresses'], options_work.merge({value_attrib: :url, search_value: 'Other'})),
      })

    end

    if @run.add_dependencies?
      target_update.merge!({
        customText3:   map_assoc(:customText3, array_search(data_custom, options_custom.merge({search_value: 'AM: Account Manager'}))),
        customText5:   map_assoc(:customText5, array_search(data_custom, options_custom.merge({search_value: 'AM: Epic IC:'}))),
        customText6:   map_assoc(:customText6, array_search(data_custom, options_custom.merge({search_value: 'AM: Epic IM:'}))),
        customText7:   map_assoc(:customText7, array_search(data_custom, options_custom.merge({search_value: 'AM: Referral Source Name'})))
      })
    end


    update_target(target_update)
    @run.increment_record!

  end

  def get_target_entity
    puts "[debug] #get_target_entity id=#{@current[:source_id]}"
    return nil if @current[:source_id].nil?
    target_entities = @target.search(@target_entity_type,"customInt1:#{@current[:source_id]}")
    if target_entities.count == 0 && !(@run.create_shell? || @run.test_only?)
      migration_failed("No target record found with source ID #{@current[:source_id]} and phase is NOT 'create_shell'")
      return nil
    end

    if target_entities.count > 1
      migration_failed("Multiple target records found with source ID #{@current[:source_id]}")
      return nil
    end

    @current[:target_entity] = target_entities[0]
    @current[:target_entity] ||= {}
    @current[:target_id] = @current[:target_entity][:id]
  end

  def update_target(update_attribs)
    msg = ''

    if @run.test_only?
      msg = "(test only)"
    else
      if @current[:target_id].blank?
        result = @target.create(@target_entity_type, update_attribs)
        @current[:target_id] = result[:changedEntityId] if result.class == Hashie::Mash && !result[:changedEntityId].nil?
      else
        result = @target.update(@target_entity_type, @current[:target_id], update_attribs)
      end

      if result.class == ServiceError
        msg = result.message
      elsif result[:errorMessage]
        # log_error("API Error: #{result.inspect}")
        result[:errors].each {|n| log_error("API Error: #{n.inspect}") } unless result[:errors].nil?
        msg = 'Target save failed: ' + result[:errorMessage] + '; ' + ( result[:errors].nil? ? '' : (result[:errors].map {|n| n.inspect}).join('; ') )
      elsif result[:changeType]
        msg = "Target record #{result[:changeType].downcase}'d"
      else
        msg = 'Unknown result'
      end
    end

    log_migration({ source_entity_type: @current[:source_entity], target_entity_id: @current[:target_id], target_before: @current[:target_entity], target_after: update_attribs, message: msg})
    msg
  end

  def update_target_assoc(assoc_attribs)
    assoc_attribs.each_pair do |assoc, attribs|
      msg_root = "Associated data #{assoc}: "
      msg = ''
      if @run.test_only?
        msg = "(test only)"
      else
        result = @target.add_association(@target_entity_type, @current[:target_id],assoc.to_s,attribs)
        if result.class == ServiceError
          msg = result.message
        elsif result[:errorMessage]
          log_error("API Error: #{result[:errorMessage]}")
          result[:errors].each {|n| log_error("API Error: #{n[:detailMessage]}") } unless result[:errors].nil?
          msg = 'Target save failed: ' + result[:errorMessage] + '; ' + ( result[:errors].nil? ? '' : (result[:errors].map {|n| n[:detailMessage]}).join('; ') )
        elsif result[:message]
          msg = result[:message]
        elsif result[:changeType]
          msg = "Target record #{result[:changeType].downcase}'d"
        else
          msg = 'Unknown result'
        end
      end
      log_migration({ source_entity_type: @current[:source_entity], target_entity_id: @current[:target_id], target_before: @current[:target_entity], target_after: {assoc => attribs}, message: msg_root + msg})
    end

    end

  def migration_failed(msg)
    log_error(msg)
    @run.ended_at = Time.now
    @run.completed_error!
  end

  def log_error(msg)
    log = @error_logs[msg]
    if log.nil?
      log = @run.migration_logs.create(log_type: MigrationLog.log_types[:error], message: msg, id_list: @current[:source_id])
      @error_logs[msg] = log
    else
      log.add_id!(@current[:source_id])
    end
  end

  # source_entity, target_entity_id, target_before, target_after, message
  def log_migration(v={})
    @run.migration_logs.create(log_type: MigrationLog.log_types[:mapped], source_id: v[:source_entity_type].id, source_before: v[:source_entity_type].to_json, target_id: v[:target_entity_id], target_before: v[:target_before].to_json, target_after: v[:target_after].to_json, message: v[:message])
  end

  def format_phone(val)
    val.nil? ? nil : number_to_phone(val.tr('()-.– ',''))
  end

  def format_address(val,line)
    val.nil? || val.blank? ? nil : val.split("\n")[line-1]
  end

  def format_travel_limit(val)
    val.nil? || val.blank? ? 0 : val.to_i
  end

  def format_comments(val)
    val.blank? ? '(no comments migrated)' : val
  end

  def format_timestamp(val)
    val.blank? ? '' : val.to_i
  end

  def format_str(val,max_len = 0)
    if max_len > 0 && val.length > max_len
      log_error("String truncation (#{max_len} chars) for: #{val}")
      val = val.truncate(max_len)
    end
    val
  end


  def map_value_array(field,array)
    new_values = []
    array.each do |val|
      new_val = map_value(field,val)
      new_values << new_val unless new_val.nil?
    end

    new_values
  end

  def map_value(field,val,parent_field=nil)
    # puts "[debug] map_value: field = #{field}, value = #{val}"
    cache_values(field, parent_field) if @mapping_values[field].nil?

    transform_val = MappingService.transform(@target.integration_type, @target_entity_type, field, val)

    return '' if transform_val.blank?
    transform_val.downcase!

    log_error("No mapped value found for '#{val}' #{val == transform_val ? '' : "(transformed to #{transform_val})"} in #{field}") if @mapping_values[field][transform_val].blank?

    @mapping_values[field][transform_val]
  end


  def cache_values(field, parent_field)
    # puts "[debug] cache_values: field = #{field}"
    meta_fields = @target.get_meta(@target_entity_type)
    log_error("No metadata for field '#{field}'") if meta_fields.empty?

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
    return '' if val.nil? || val.blank?
    cache_assoc(field, val) if @mapping_assoc[field].nil? || @mapping_assoc[field][val].nil?

    { id: @mapping_assoc[field][val] }
  end

  def cache_assoc(field, val)
    assoc_entities = @target.search(field,"customInt1:#{val}")
    @mapping_assoc[field] ||= {}
    @mapping_assoc[field][val] = assoc_entities.count == 1 ? assoc_entities[0].id : ''
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
          msg = options[:description].blank? ? "'#{options[:value_attrib]}' (where '#{options[:search_attrib]}' = '#{options[:search_value]}')" : options[:description]
          log_error "Multiple values found for #{msg}. No value migrated"
          return nil
        end
      end
    end
    value
  end



end