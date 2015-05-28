class MigrationService
  include ActionView::Helpers::NumberHelper

  attr_reader :error, :valid_entity_maps, :mapping_values, :mapping_assoc
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
    @source_maps = {}
    @valid_entity_maps = {
      :highrise => {
        :bullhorn => {
            :company => :client_corporation,
            :person => [:candidate, :client_contact],
            :deal => :job_order
        }
      }
    }
    @current = {}
    @abort_last_check_at = Time.now

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
        log_error("Could not find entity with ID #{@current[:source_id]} in #{@source.system_type}")
      else
        begin
          @current[:source_entity] = entity
          self.send "migrate_#{@source_entity_type}"
        rescue => e
          log_exception(e)
        end
        @run.increment_record!
      end
      break if abort_run
    end
    @current = {}

    if @run.all_records
      page = @run.start_page.nil? ? 1 : @run.start_page
      max = (@run.max_records == -1) ? 0 : @run.max_records
      begin
        entities = @source.retrieve(@source_entity_type,nil,page)
        max = max + entities.count
        @run.update(max_records: max)
        entities.each do |entity|
          begin
            @current = { source_id: entity.id, source_entity: entity }
            self.send "migrate_#{@source_entity_type}"
          rescue => e
            log_exception(e)
          end
          @run.increment_record!
          break if abort_run
        end
        @current = {}
        page = page + 1
        break if abort_run
      end while entities.count > 0
    end

    @run.ended_at = Time.now
    if @run.abort_at
      @run.aborted!
    elsif @run.migration_logs.exception.count > 0
      @run.failed!
    elsif @error_logs.keys.count > 0
      @run.completed_error!
    else
      @run.completed_success!
    end

  end

  def abort_run
    puts "[debug] MigrationService#abort_run check: #{Time.now}"
    @run.reload if @abort_last_check_at < 10.seconds.ago
    @run.abort_at
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

  def rescue_after_error(e)
    @run.ended_at = Time.now
    @run.failed!
    log_exception(e)
  end

  def migrate_person
    puts "[debug] #migrate_person id=#{@current[:source_id]}"

    source_entity = @current[:source_entity]
    data_custom = source_entity.subject_datas.map {|n| n.attributes} #if source_entity.respond_to?(:subject_datas)

    target_type = array_search(data_custom, options_custom.merge({search_value: 'zzz Migration Flag- Contact vs Candidate'}))

    if target_type.blank?
      log_error("'Migration Flag - Contact vs Candidate' field not set")
    elsif (target_type.downcase == 'contact')
      @target_entity_type = :client_contact
      migrate_person_to_contact
    elsif (target_type.downcase == 'candidate')
      @target_entity_type = :candidate
      migrate_person_to_candidate
    else
      log_error("'Migration Flag - Contact vs Candidate' value not recognized: '#{target_type}'")
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
      client_corp_obj = map_assoc(:client_corporation, 'customInt1', source_entity.company_id)
      if client_corp_obj[:id].blank?
        log_error("Prerequisite not available: Company=#{source_entity.company_id}")
        return
      end

      contact_name = map_assoc(:client_corporation, 'customInt1', source_entity.company_id, :customText3)[:customText3]
      contact_obj = map_assoc(:corporate_user, 'name', contact_name)

      # Email hierarchy: Use 'work', 'home', 'other' - as found in Highrise, up to 3

      emails = array_search_multi(data_contact['email_addresses'], options_work.merge({value_attrib: :address, description: 'work email'}))
      emails = emails + array_search_multi(data_contact['email_addresses'], options_home.merge({value_attrib: :address, description: 'home email'}))
      emails = emails + array_search_multi(data_contact['email_addresses'], options_home.merge({value_attrib: :address, search_value: 'Other', description: 'other email'}))

      if emails.count < 1
        log_error('Required field not available: email')
        return
      end

      target_update.merge!({
         firstName: source_entity.first_name,
         lastName: source_entity.last_name,
         name: source_entity.first_name + ' ' + source_entity.last_name,
         customInt1: @current[:source_id],
         dateAdded: format_timestamp(source_entity.created_at),
         occupation: format_str(source_entity.title,50),
         mobile: format_phone(array_search(data_contact['phone_numbers'], options_work.merge({value_attrib: :number, search_value: 'Mobile'}))),
         phone: format_phone(array_search(data_contact['phone_numbers'], options_work.merge({value_attrib: :number}))),
         email: emails[0],
         email2: emails.count > 1 ? emails[1] : '',
         email3: emails.count > 2 ? emails[2] : '',
         address: {
             address1:  format_address( array_search(data_contact['addresses'], options_work.merge({value_attrib: :street})),1),
             address2:  format_address( array_search(data_contact['addresses'], options_work.merge({value_attrib: :street})),2),
             city:                      array_search(data_contact['addresses'], options_work.merge({value_attrib: :city})),
             state:     map_value(:state, array_search(data_contact['addresses'], options_work.merge({value_attrib: :state})), :address),
             zip:                       array_search(data_contact['addresses'], options_work.merge({value_attrib: :zip})),
             countryID: map_value(:countryID, array_search(data_contact['addresses'], options_work.merge({value_attrib: :country})), :address)
         },
         clientCorporation: client_corp_obj,
         customText1: source_entity.linkedin_url,
         customTextBlock1: format_textbox(source_entity.background)
      })
      target_update.merge!({owner: contact_obj}) unless contact_obj.empty?

      update_target(target_update)
    end

  end

  def migrate_person_to_candidate
    puts "[debug] #migrate_person_to_candidate id=#{@current[:source_id]}"
    get_target_entity
    return if @current[:target_entity].nil?  # failed

    source_entity = @current[:source_entity]
    target_update = {}
    target_update_assoc = {}
    data_contact = source_entity.contact_data.attributes
    data_custom = source_entity.respond_to?(:subject_datas) ? source_entity.subject_datas.map {|n| n.attributes} : []

    if @run.test_only? || @run.create_shell?
      emails = array_search_multi(data_contact['email_addresses'], options_work.merge({value_attrib: :address, description: 'work email'}))
      emails = emails + array_search_multi(data_contact['email_addresses'], options_home.merge({value_attrib: :address, description: 'home email'}))
      emails = emails + array_search_multi(data_contact['email_addresses'], options_home.merge({value_attrib: :address, search_value: 'Other', description: 'other email'}))

      referred_by_name = array_search(data_custom, options_custom.merge({search_value: 'Rec: Referred By'}))
      referred_by_assoc = {}
      unless referred_by_name.blank?
        if referred_by_assoc[:id].blank?
          referred_by_assoc = map_assoc(:corporate_user, 'name', referred_by_name)
          referred_by_assoc[:_subType] = 'CorporateUser' unless referred_by_assoc[:id].blank?
        end

        if referred_by_assoc[:id].blank?
          referred_by_assoc = map_assoc(:candidate, 'name', referred_by_name)
          referred_by_assoc[:_subType] = 'Candidate' unless referred_by_assoc[:id].blank?
        end

        if referred_by_assoc[:id].blank?
          referred_by_assoc = map_assoc(:client_contact, 'name', referred_by_name)
          referred_by_assoc[:_subType] = 'ClientContact' unless referred_by_assoc[:id].blank?
        end
      end
      referred_by_name = nil unless referred_by_assoc[:id].blank?

      current_blueleaf = map_value(:customText15, array_search(data_custom,options_custom.merge({search_value: 'HR: Current BlueLeaf?'})))
      blueleaf_employment = array_search(data_custom,options_custom.merge({search_value: 'HR: Employment Model (W2/1099 (#%/#%))'}))
      current_employment_mapped = map_value(:customText16, blueleaf_employment)

      if current_blueleaf.blank?
        current_employment_model = nil
        current_employment_txt = nil
        employment_pref = blueleaf_employment
      else
        current_employment_model = current_employment_mapped
        current_employment_txt = current_employment_mapped.blank? ? blueleaf_employment : nil
        employment_pref = nil
      end

      vetted_notes = []
      vetted_notes << array_search(data_custom,options_custom.merge({search_value: 'Rec: Vetted by #1'}))
      vetted_notes << array_search(data_custom,options_custom.merge({search_value: 'Rec: Vetted by #2'}))
      vetted_notes << array_search(data_custom,options_custom.merge({search_value: 'Rec: Vetted by #3'}))
      comments = []
      comments << "HR Rec/Placement Note: " + array_search(data_custom,options_custom.merge({search_value: 'Rec: Recruitment/Placement Notes'})).to_s
      comments << ''
      comments << "HR Quality Comment: " + array_search(data_custom,options_custom.merge({search_value: 'Rec: BlueTree Quality R/Y/G Comments'})).to_s
      owner = map_assoc(:corporate_user, :name, array_search(data_custom, options_custom.merge({search_value: 'Rec: Primary Contact / Advocate / Manager'})))

      # dateAdded: format_timestamp(source_entity.created_at),
      target_update.merge!({
          firstName: source_entity.first_name,
          lastName: source_entity.last_name,
          name: source_entity.first_name.to_s + ' ' + source_entity.last_name.to_s,
          customInt1: @current[:source_id],
          companyName: source_entity.company_name,
          companyURL: source_entity.linkedin_url,
          occupation: format_str(source_entity.title,50),
          status: 'HR Migration',
          email: emails[0],
          email2: emails.count > 1 ? emails[1] : '',
          email3: emails.count > 2 ? emails[2] : '',
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
          dateAvailable: format_timestamp(array_search(data_custom,options_custom.merge({search_value: 'Rec: Available after:'}))),
          travelLimit: format_travel_limit(array_search(data_custom,options_custom.merge({search_value: 'Rec: Max Travel %'}))),
          referredBy: referred_by_name,
          referredByPerson: nil,
          customText1: map_value(:customText1, array_search(data_custom, options_custom.merge({search_value: 'Rec: Open to BlueTree Roles?'}))),
          customText3: map_value(:customText3, array_search(data_custom,options_custom.merge({search_value: 'Rec: Interested in Canopy?'}))),
          customText4: map_value(:customText4, array_search(data_custom, options_custom.merge({search_value: 'Rec: BlueTree Quality (Red/Yellow/Green)'}))),
          customText15: current_blueleaf,
          customText16: current_employment_model,
          customText17: employment_pref,
          customTextBlock2: format_textbox(source_entity.background),
          customTextBlock3: format_textbox_array(comments),
          customTextBlock4: format_textbox(current_employment_txt),
          customTextBlock5: format_textbox_array(vetted_notes)
      })

      target_update.merge!({owner: owner}) unless owner.empty?
      target_update.merge!({referredByPerson: referred_by_assoc}) unless referred_by_assoc.empty?
      mapped_apps = MappingService.map_highrise_apps(data_custom)
      target_update.merge!({customText7: map_value_array(:customText7,mapped_apps[:p])}) unless mapped_apps[:p].nil? || mapped_apps[:p].count==0
      target_update.merge!({customText6: map_value_array(:customText6,mapped_apps[:t])}) unless mapped_apps[:t].nil? || mapped_apps[:t].count==0
      target_update_assoc.merge!({primarySkills: map_value_array(:primarySkills,mapped_apps[:q])}) unless mapped_apps[:q].nil? || mapped_apps[:q].count==0
      target_update.merge!({customText12: map_value_array(:customText12,mapped_apps[:c])}) unless mapped_apps[:c].nil? || mapped_apps[:c].count==0
      mapped_apps[:unknown].each { |app| log_error("Unknown ZCONAPP value: '#{app}'") } unless mapped_apps[:unknown].nil?

      mapped_roles = MappingService.map_highrise_roles(data_custom)
      target_update.merge!({customText8:  map_value_array(:customText8, mapped_roles[:p])}) unless mapped_roles[:p].nil? || mapped_roles[:p].count==0
      target_update.merge!({customText13: map_value_array(:customText13,mapped_roles[:s])}) unless mapped_roles[:s].nil? || mapped_roles[:s].count==0
      q_roles = mapped_roles[:q].nil? ? [] : mapped_roles[:q]
      e_roles = mapped_roles[:e].nil? ? [] : mapped_roles[:e]
      target_update_assoc.merge!({specialties: map_value_array(:specialties,q_roles + e_roles)}) unless (q_roles + e_roles).count==0
      mapped_roles[:unknown].each { |role| log_error("Unknown ZCONROLE value: '#{role}'") } unless mapped_roles[:unknown].nil?
    end


    # Need to map certs/roles => add_candidate_association
    update_target(target_update)
    update_target_assoc(target_update_assoc) unless target_update_assoc.empty?
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
        companyURL:    format_str(array_search(data_contact['web_addresses'], options_work.merge({value_attrib: :url})),100),
        customText2:   array_search(data_contact['email_addresses'], options_work.merge({value_attrib: :address, description: 'work email'})),
        customText3:   array_search(data_custom, options_custom.merge({search_value: 'AM: Account Manager'})),
        customText4:   map_value(:customText4, array_search(data_custom, options_custom.merge({search_value: 'AM: Category'}))),
        customText5:   array_search(data_custom, options_custom.merge({search_value: 'AM: Epic IC:'})),
        customText6:   array_search(data_custom, options_custom.merge({search_value: 'AM: Epic IM:'})),
        customText7:   array_search(data_custom, options_custom.merge({search_value: 'AM: Referral Source Name'})),
        customText8:   map_value(:customText8, array_search(data_custom, options_custom.merge({search_value: 'AM: Referral Source Type'}))),
        customText9:   array_search(data_custom, options_custom.merge({search_value: 'AM: RFA Terms'})),
        customText10:  map_value(:customText10, array_search(data_custom, options_custom.merge({search_value: "AM: SOW (BlueTree's or Client's)"}))),
        customText11:  map_value(:customText11, array_search(data_custom, options_custom.merge({search_value: "HR: HCO requires purchase order ID?"}))),
        customText12:  format_str(array_search(data_contact['web_addresses'], options_work.merge({value_attrib: :url, search_value: 'Other'})),100)
      })

    end

    update_target(target_update)
  end

  def migrate_deal
    puts "[debug] #migrate_deal id=#{@current[:source_id]}"

    get_target_entity
    return if @current[:target_entity].nil?  # failed
    source_entity = @current[:source_entity]

    target_update = {}

    if @run.test_only? || @run.create_shell?
      client_corp_obj = map_assoc(:client_corporation, 'customInt1', source_entity.party_id)
      if client_corp_obj[:id].blank?
        log_error("Prerequisite not available: Company=#{source_entity.party_id}")
        return
      end

      client_contact_obj = map_assoc(:client_contact, 'customInt1', MappingService.get_hr_deal_owner(@current[:source_id]))
      if client_contact_obj[:id].blank?
        log_error("Prerequisite not available: Contact=#{MappingService.get_hr_deal_owner(@current[:source_id])}")
        return
      end

      owner_name = get_source_name(:user, source_entity.responsible_party_id)
      owner_obj = map_assoc(:corporate_user, 'name', owner_name)
      if owner_obj[:id].blank?
        log_error("Prerequisite not available: Sales Owner=#{owner_name} (#{source_entity.responsible_party_id})")
        return
      end

      employment_type = map_value(:employmentType,source_entity.category.name)
      priority = source_entity.name.match(/\[P:(\d+)\]/) ? source_entity.name.match(/\[P:(\d+)\]/)[1] : 3

      target_update.merge!({
             title: format_str(source_entity.name,100),
             customInt1: @current[:source_id],
             clientCorporation: client_corp_obj,
             clientContact: client_contact_obj,
             description: format_textbox_html(source_entity.background),
             employmentType: employment_type,
             owner: owner_obj,
             clientBillRate: source_entity.price_type == 'hour' ? source_entity.price : nil,
             isOpen: (source_entity.status == 'pending'),
             status: map_value(:status,source_entity.category.name),
             startDate: format_timestamp(source_entity.created_at),
             salaryUnit: map_value(:salaryUnit, source_entity.price_type),
             type: priority
         })

      case employment_type
        when 'Contract', 'Contract (C2C)'
          target_update.merge!({clientBillRate: source_entity.price})
        when 'Permanent - FTE'
          target_update.merge!({salary: source_entity.price})
        else
          target_update.merge!({payrate: source_entity.price})
      end

      update_target(target_update)
    end
  end

  def get_target_entity
    puts "[debug] #get_target_entity id=#{@current[:source_id]} => #{@target_entity_type}"
    # return nil if @current[:source_id].nil?
    target_entities = search_assoc(@target_entity_type,'customInt1',@current[:source_id])
    puts "[debug] #get_target_entity: results = #{target_entities.inspect}"
    if target_entities.class == ServiceError || target_entities[0].class == ServiceError
      log_error("Error retrieving target: #{target_entities[0].message}")
      return nil
    end

    if target_entities.count == 0 && !(@run.create_shell? || @run.test_only?)
      log_error("No target record found with source ID #{@current[:source_id]} and phase is NOT 'create_shell'")
      return nil
    end

    if target_entities.count > 1
      log_error("Multiple target records found with source ID #{@current[:source_id]}")
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

  def log_exception(e)
    msg = "Exception: #{e.message} | Backtrace: #{e.backtrace.inspect}"
    id = @current.nil? ? nil : @current[:source_id]
    @run.migration_logs.create(log_type: MigrationLog.log_types[:exception], message: msg, id_list: id)
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

  def format_textbox_array(val_array)
    val_array.count == 0 ? nil : val_array.map {|n| format_textbox(n)}.join("\r\n")
  end

  def format_textbox(val)
    val.blank? ? nil : val.gsub("\n","\r\n")
  end

  def format_textbox_html(val)
    val.blank? ? nil : "<p>" + val.gsub("\n","<br>") + "</p>"

  end

  def format_timestamp(val)
    puts "[debug] format_timestamp: val=#{val} (#{val.class})"
    return nil if val.blank?
    val = val.to_time if val.class == String
    val.to_i == 0 ? nil : val.to_i*1000
  end

  def format_str(val,max_len = 0)
    return nil if val.nil?
    if max_len > 0 && val.length > max_len
      log_error("String truncation (#{max_len} chars) for: #{val}")
      val = val.truncate(max_len)
    end
    val
  end


  def map_value_array(field,array)
    return nil if array.nil?
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
    transform_val.strip!

    log_error("No mapped value found for '#{val}' #{val == transform_val ? '' : "(transformed to #{transform_val})"} in #{field}") if @mapping_values[field][transform_val].blank?

    @mapping_values[field][transform_val]
  end


  def cache_values(field, parent_field)
    # puts "[debug] cache_values: field = #{field}"
    meta_fields = @target.get_meta(@target_entity_type)
    log_error("No metadata for field '#{field}'") if meta_fields.empty?

    if meta_fields[0].class == ServiceError
      log_error("Error retrieving field '#{field}' metadata: #{meta_fields[0].message}")
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

  def map_assoc(entity, field, val, attrib = :id)
    return {} if val.nil? || val.blank?
    val = val.to_i if field == 'customInt1'  #force it to int
    cache_assoc(entity, field, val) if @mapping_assoc[entity].nil? || @mapping_assoc[entity][field].nil? || @mapping_assoc[entity][field][val].nil?

    return {} if @mapping_assoc[entity][field][val][attrib].blank?
    { attrib => @mapping_assoc[entity][field][val][attrib] }
  end

  def cache_assoc(entity, field, val)
    assoc_entities = search_assoc(entity, field, val)
    if assoc_entities.class == ServiceError || assoc_entities[0].class == ServiceError
      log_error("Error retrieving associated records: #{assoc_entities[0].message}")
      assoc_entity = Hashie::Mash.new
    else
      assoc_entity = assoc_entities.count == 1 ? assoc_entities[0] : Hashie::Mash.new
    end
    @mapping_assoc[entity] ||= {}
    @mapping_assoc[entity][field] ||= {}
    @mapping_assoc[entity][field][val] = assoc_entity
  end

  def search_assoc(entity,field,val)
    return nil if val.blank?
    val = val.to_i if field == 'customInt1'  #force it to int
    if entity == :candidate
      qval = val.class == String ? double_quote(val) : val
      query = "#{field.to_s}:#{qval}"
    else
      qval = val.class == String ? single_quote(val) : val
      query = "#{field.to_s}=#{qval}"
    end
    @target.search(entity,query)
  end

  def get_source_name(entity,id)
    return nil if id.blank?
    if @source_maps[entity].blank? || @source_maps[entity][id].blank?
      cache_source(entity,id)
    end

    @source_maps[entity][id].nil? ? '' : @source_maps[entity][id].name
  end

  def cache_source(entity,id)
    return nil if id.blank?
    val = @source.get(entity,id)
    @source_maps[entity] ||= {}
    @source_maps[entity][id] = val
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

  def array_search_multi(array,options = {})
    # puts "[debug] array_search: options = #{options}"
    value = []
    array ||= []
    array.each do |obj|
      hash = obj.class.to_s.include?('Highrise') ? obj.attributes : obj
      if hash[options[:search_attrib]].to_s == options[:search_value].to_s
        value << hash[options[:value_attrib]]
      end
    end
    value
  end

  def single_quote(val)
    "'" + val + "'"
  end

  def double_quote(val)
    '"' + val + '"'
  end

end