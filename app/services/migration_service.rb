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
            :deal => :job_order,
            :task => :task
        }
      }
    }
    @current = {}
    @abort_last_check_at = Time.now
    @notes_count = {}
    @comments_count = {}

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
    return unless @run.created? || @run.queued?  # abort if the status has already been changed
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
          if @run.test_only? || @run.create_record? || @run.catchup_all?
            self.send "migrate_#{@source_entity_type}"
          end

          if @run.load_history? || @run.update_history? || @run.catchup_all?
            migrate_history
          end
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
      from_timestamp = @run.from_date.nil? ? nil : @run.from_date.to_time(:local).utc
      begin
        entities = @source.retrieve(@source_entity_type,from_timestamp,page)
        max = max + entities.count
        @run.update(max_records: max)
        entities.each do |entity|
          begin
            @current = { source_id: entity.id, source_entity: entity }
            if @run.test_only? || @run.create_record? || @run.catchup_all?
              self.send "migrate_#{@source_entity_type}"
            end

            if @run.load_history? || @run.update_history? || @run.catchup_all?
              migrate_history
            end
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

  def get_target_type(source_type = @source_entity_type, source_entity = @current[:source_entity], skip_error_logs = false)
    puts "[debug] #get_target_type: source_type = #{source_type} (#{source_type.class})"
    val = nil
    if source_type.to_sym == :person
      data_custom = source_entity.respond_to?(:subject_datas) ? source_entity.subject_datas.map {|n| n.attributes} : []
      target_type = array_search(data_custom, options_custom.merge({search_value: 'zzz Migration Flag- Contact vs Candidate'}))
      # puts "[debug] #get_target_type: target_type = #{target_type}"

      if target_type.blank?
        log_error("'Migration Flag - Contact vs Candidate' field not set") unless skip_error_logs
      elsif target_type.downcase == 'contact'
        val = :client_contact
      elsif target_type.downcase == 'candidate'
        val = :candidate
      else
        log_error("'Migration Flag - Contact vs Candidate' value not recognized: '#{target_type}'") unless skip_error_logs
      end
    else
      val = @valid_entity_maps[@source.integration_type.to_sym][@target.integration_type.to_sym][source_type.to_sym]
    end

    val
  end

  def migrate_person
    puts "[debug] #migrate_person id=#{@current[:source_id]}"
    if @current[:source_entity].respond_to?(:visible_to) && @current[:source_entity].visible_to != 'Everyone'
      puts "[debug] #migrate_person: Record not visible - ignoring"
      log_error("Record not visible to everyone - only '#{@current[:source_entity].visible_to}'")
      return
    end

    target_type = get_target_type

    if target_type == :candidate
      @target_entity_type = :candidate
      migrate_person_to_candidate
    elsif target_type == :client_contact
      @target_entity_type = :client_contact
      migrate_person_to_contact
    else
      log_error("Unknown target record type for Person: #{target_type}")
    end
  end

  def migrate_person_to_contact
    puts "[debug] #migrate_person_to_contact id=#{@current[:source_id]}"
    get_target_entity
    return if @current[:target_entity].nil?  # failed

    source_entity = @current[:source_entity]
    target_update = {}
    data_contact = source_entity.respond_to?(:contact_data) ? source_entity.contact_data.attributes : []
    data_custom = source_entity.respond_to?(:subject_datas) ? source_entity.subject_datas.map {|n| n.attributes} : []

    if source_entity.company_id.blank?
      log_error("No company in Highrise - applying default")
      client_corp_obj = map_assoc(:client_corporation, 'customInt1', MappingService::DEFAULT_COMPANY)
    else
      client_corp_obj = map_assoc(:client_corporation, 'customInt1', source_entity.company_id)
    end

    if client_corp_obj[:id].blank?
      log_error("Missing Company=#{source_entity.company_id} - not migrating Contact")
      return
    end

    contact_name = map_assoc(:client_corporation, 'customInt1', source_entity.company_id, :customText3)[:customText3]
    contact_obj = map_assoc(:corporate_user, 'name', contact_name)

    # Email hierarchy: Use 'work', 'home', 'other' - as found in Highrise, up to 3

    emails = array_search_multi(data_contact['email_addresses'], options_work.merge({value_attrib: :address, description: 'work email'}))
    emails = emails + array_search_multi(data_contact['email_addresses'], options_home.merge({value_attrib: :address, description: 'home email'}))
    emails = emails + array_search_multi(data_contact['email_addresses'], options_home.merge({value_attrib: :address, search_value: 'Other', description: 'other email'}))
    emails[0] = 'unknown' if emails.count < 1
    if emails.count > 3
      log_error("More than 3 email addresses")
    end

    other_phone = array_search(data_contact['phone_numbers'], options_home.merge({value_attrib: :number}))
    other_phone = array_search(data_contact['phone_numbers'], options_home.merge({value_attrib: :number, search_value: 'Other'})) if other_phone.blank?

    target_update.merge!({
       firstName: truncate_name(source_entity.first_name),
       lastName: truncate_name(source_entity.last_name),
       name: truncate_name(source_entity.first_name) + ' ' + truncate_name(source_entity.last_name),
       customInt1: @current[:source_id],
       dateAdded: format_timestamp(source_entity.created_at),
       status: 'HR Migration',
       occupation: format_str(source_entity.title,50),
       mobile: format_phone(array_search(data_contact['phone_numbers'], options_work.merge({value_attrib: :number, search_value: 'Mobile'}))),
       phone: format_phone(array_search(data_contact['phone_numbers'], options_work.merge({value_attrib: :number}))),
       phone2: format_phone(other_phone),
       fax: format_phone(array_search(data_contact['phone_numbers'], options_work.merge({value_attrib: :number, search_value: 'Fax'}))),
       email: emails[0],
       email2: emails.count > 1 ? emails[1] : '',
       email3: emails.count > 2 ? emails[2] : '',
       address: {
           address1:  format_address( array_search(data_contact['addresses'], options_work.merge({value_attrib: :street}))),
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

  def migrate_person_to_candidate
    puts "[debug] #migrate_person_to_candidate id=#{@current[:source_id]}"
    get_target_entity
    return if @current[:target_entity].nil?  # failed

    source_entity = @current[:source_entity]
    target_update = {}
    target_update_assoc = {}
    data_contact = source_entity.respond_to?(:contact_data) ? source_entity.contact_data.attributes : []
    data_custom = source_entity.respond_to?(:subject_datas) ? source_entity.subject_datas.map {|n| n.attributes} : []

    emails = array_search_multi(data_contact['email_addresses'], options_work.merge({value_attrib: :address, description: 'work email'}))
    emails = emails + array_search_multi(data_contact['email_addresses'], options_home.merge({value_attrib: :address, description: 'home email'}))
    emails = emails + array_search_multi(data_contact['email_addresses'], options_home.merge({value_attrib: :address, search_value: 'Other', description: 'other email'}))
    if emails.count > 3
      log_error("More than 3 email addresses")
    end

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
    rec_note_text = array_search(data_custom,options_custom.merge({search_value: 'Rec: Recruitment/Placement Notes'}))
    quality_text = array_search(data_custom,options_custom.merge({search_value: 'Rec: BlueTree Quality R/Y/G Comments'}))
    comments << "HR Rec/Placement Note: " + rec_note_text unless rec_note_text.blank?
    comments << '' unless rec_note_text.blank? || quality_text.blank?
    comments << "HR Quality Comment: " + quality_text unless quality_text.blank?
    owner = map_assoc(:corporate_user, :name, array_search(data_custom, options_custom.merge({search_value: 'Rec: Primary Contact / Advocate / Manager'})))

    other_phone = array_search(data_contact['phone_numbers'], options_home.merge({value_attrib: :number}))
    other_phone = array_search(data_contact['phone_numbers'], options_home.merge({value_attrib: :number, search_value: 'Other'})) if other_phone.blank?

    employ_pref = []
    employ_pref << map_value(:employmentPreference, array_search(data_custom,options_custom.merge({search_value: 'Rec: FTE preferences (Local only; Open to relocation; Not interested)'})))
    employ_pref << map_value(:employmentPreference, array_search(data_custom,options_custom.merge({search_value: 'Rec: Interested in salary?'})))

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
        phone2: format_phone(other_phone),
        address: {
            address1:  format_address( array_search(data_contact['addresses'], options_home.merge({value_attrib: :street}))),
            city:                      array_search(data_contact['addresses'], options_home.merge({value_attrib: :city})),
            state:     map_value(:state, array_search(data_contact['addresses'], options_home.merge({value_attrib: :state})), :address),
            zip:                       array_search(data_contact['addresses'], options_home.merge({value_attrib: :zip})),
            countryID: map_value(:countryID, array_search(data_contact['addresses'], options_home.merge({value_attrib: :country})), :address)
        },
        secondaryAddress: {
            address1:  format_address( array_search(data_contact['addresses'], options_work.merge({value_attrib: :street}))),
            city:                      array_search(data_contact['addresses'], options_work.merge({value_attrib: :city})),
            state:     map_value(:state, array_search(data_contact['addresses'], options_work.merge({value_attrib: :state})), :address),
            zip:                       array_search(data_contact['addresses'], options_work.merge({value_attrib: :zip})),
            countryID: map_value(:countryID, array_search(data_contact['addresses'], options_work.merge({value_attrib: :country})), :address)
        },
        employmentPreference: employ_pref,
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

    if owner.empty?
      log_error("Missing advocate")
    else
      target_update.merge!({owner: owner})
    end
    target_update.merge!({referredByPerson: referred_by_assoc}) unless referred_by_assoc.empty?
    mapped_apps = MappingService.map_highrise_apps(data_custom)
    target_update.merge!({customText7: map_value_array(:customText7,mapped_apps[:p])}) unless mapped_apps[:p].nil? || mapped_apps[:p].count==0
    target_update.merge!({customText6: map_value_array(:customText6,mapped_apps[:t])}) unless mapped_apps[:t].nil? || mapped_apps[:t].count==0
    target_update.merge!({customText18: map_value_array(:customText18,mapped_apps[:q])}) unless mapped_apps[:q].nil? || mapped_apps[:q].count==0
    # target_update_assoc.merge!({primarySkills: map_value_array(:primarySkills,mapped_apps[:q])}) unless mapped_apps[:q].nil? || mapped_apps[:q].count==0
    target_update.merge!({customText12: map_value_array(:customText12,mapped_apps[:c])}) unless mapped_apps[:c].nil? || mapped_apps[:c].count==0
    mapped_apps[:unknown].each { |app| log_error("Unknown ZCONAPP value: '#{app}'") } unless mapped_apps[:unknown].nil?

    mapped_roles = MappingService.map_highrise_roles(data_custom)
    target_update.merge!({customText8:  map_value_array(:customText8, mapped_roles[:p])}) unless mapped_roles[:p].nil? || mapped_roles[:p].count==0
    target_update.merge!({customText13: map_value_array(:customText13,mapped_roles[:s])}) unless mapped_roles[:s].nil? || mapped_roles[:s].count==0
    q_roles = mapped_roles[:q].nil? ? [] : mapped_roles[:q]
    e_roles = mapped_roles[:e].nil? ? [] : mapped_roles[:e]
    target_update.merge!({customText19: map_value_array(:customText19,q_roles + e_roles)}) unless (q_roles + e_roles).count==0
    # target_update_assoc.merge!({specialties: map_value_array(:specialties,q_roles + e_roles)}) unless (q_roles + e_roles).count==0
    mapped_roles[:unknown].each { |role| log_error("Unknown ZCONROLE value: '#{role}'") } unless mapped_roles[:unknown].nil?

    update_target(target_update)
    update_target_assoc(target_update_assoc) unless target_update_assoc.empty?
  end

  def migrate_company
    puts "[debug] #migrate_company id=#{@current[:source_id]}"

    if @current[:source_entity].respond_to?(:visible_to) && @current[:source_entity].visible_to != 'Everyone'
      log_error("Record not visible to everyone - only '#{@current[:source_entity].visible_to}'")
      return
    end

    get_target_entity
    return if @current[:target_entity].nil?  # failed
    source_entity = @current[:source_entity]

    target_update = {}
    data_contact = source_entity.respond_to?(:contact_data) ? source_entity.contact_data.attributes : []
    data_custom = source_entity.respond_to?(:subject_datas) ? source_entity.subject_datas.map {|n| n.attributes} : []

    target_update.merge!({
      name: source_entity.name,
      customInt1: @current[:source_id],
      status: map_value(:status, array_search(data_custom, options_custom.merge({search_value: 'AM: Status'}))),
      phone:         format_phone(   array_search(data_contact['phone_numbers'], options_work.merge({value_attrib: :number}))),
      address: {
          address1:  format_address( array_search(data_contact['addresses'], options_work.merge({value_attrib: :street}))),
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
      customText15:  format_str(array_search(data_contact['web_addresses'], options_work.merge({value_attrib: :url, search_value: 'Other'})),100),
      companyDescription: format_textbox(source_entity.background)

    })

    update_target(target_update)
  end

  def migrate_deal
    puts "[debug] #migrate_deal id=#{@current[:source_id]}"

    get_target_entity
    return if @current[:target_entity].nil?  # failed
    source_entity = @current[:source_entity]

    target_update = {}

    if source_entity.party_id.blank?
      log_error("Blank Company - applying default")
      client_corp_id = MappingService::DEFAULT_COMPANY
    else
      client_corp_id = source_entity.party_id
    end
    client_corp_obj = map_assoc(:client_corporation, 'customInt1', client_corp_id)
    client_corp_name_obj = map_assoc(:client_corporation,'customInt1',client_corp_id, :name)  # should be cached now

    if client_corp_obj[:id].blank?
      log_error("Missing Company=#{source_entity.party_id} - not migrating deal")
      return
    end

    client_contact_obj = get_corporation_contact(client_corp_name_obj[:name])

    owner_name = get_source_name(:user, source_entity.responsible_party_id)
    owner_obj = map_assoc(:corporate_user, 'name', owner_name)
    if owner_obj[:id].blank?
      log_error("Missing Owner=#{owner_name} (#{source_entity.responsible_party_id}) - applying default")
      owner_obj = nil
    end

    employment_type = source_entity.respond_to?(:category) ? map_value(:employmentType,source_entity.category.name) : 'Other'
    priority = source_entity.name.match(/\[P:(\d+)\]/) ? source_entity.name.match(/\[P:(\d+)\]/)[1] : 3

    if source_entity.status == 'won'
      status = 'Won'
    elsif source_entity.respond_to?(:category)
      status = map_value(:status,source_entity.category.name)
    else
      status = 'None'
    end

    target_update.merge!({
           title: format_str(source_entity.name,100),
           customInt1: @current[:source_id],
           clientCorporation: client_corp_obj,
           clientContact: client_contact_obj,
           description: format_textbox_html(source_entity.background),
           employmentType: employment_type,
           clientBillRate: source_entity.price_type == 'hour' ? source_entity.price : nil,
           isOpen: (source_entity.status == 'pending'),
           status: status,
           startDate: format_timestamp(source_entity.created_at),
           salaryUnit: map_value(:salaryUnit, source_entity.price_type),
           type: priority
       })
    target_update.merge!({owner: owner_obj }) unless owner_obj.nil?

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

  def migrate_history
    puts "[debug] #migrate_history type=#{@source_entity_type} | id=#{@current[:source_id]}"
    source_entity = @current[:source_entity]

    @target_entity_type = get_target_type if @source_entity_type.to_sym == :person
    get_target_entity
    if @current[:target_id].blank?
      log_error("Missing target record #{@target_entity_type} for #{@source_entity_type}=#{@current[:source_id]}")
      return
    end

    @target_reference = {}
    @target_person = {}
    if @target_entity_type.to_sym == :candidate
      @target_reference = {candidates: {id: @current[:target_id]}}
      @target_person = {id: @current[:target_id], _subtype: 'Candidate'}
    elsif @target_entity_type.to_sym == :client_contact
      @target_reference = {clientContacts: {id: @current[:target_id]}}
      @target_person = {id: @current[:target_id], _subtype: 'ClientContact'}
    elsif @target_entity_type == :job_order
      @target_reference = {jobOrder: {id: @current[:target_id]}}
      @target_person = {id: @current[:target_entity][:clientContact][:id], _subtype: 'ClientContact'}
    elsif @target_entity_type == :client_corporation
      client_obj = get_corporation_contact(@current[:target_entity][:name])
      @target_reference = {clientContacts: client_obj}
      @target_person = client_obj
    else
      log_error("No target person defined for type = #{@target_entity_type} - notes not migrated")
      return
    end

    if @target_person[:id].blank?
      log_error("No target person found for #{@target_entity_type} = #{@current[:target_id]} - notes not migrated")
      return
    end

    @notes_count = {success: 0, failed: 0}
    @comments_count = {success: 0, failed:0, current_note: 0}
    @new_notes = []

    from_timestamp = @run.from_date.nil? ? nil : @run.from_date.to_time(:local).utc
    through_timestamp = @run.through_date.nil? ? nil : @run.through_date.to_time(:local).utc
    if from_timestamp
      source_entity.notes_each_since(from_timestamp) do |note|
        migrate_note(note) if through_timestamp.nil? || through_timestamp > note.created_at
      end
      unless @source_entity_type.to_sym == :company  # companies don't have emails
        source_entity.emails_each_since(from_timestamp) do |email|
          migrate_email(email)  if through_timestamp.nil? || through_timestamp > email.created_at
        end
      end
    else
      source_entity.notes_each do |note|
        migrate_note(note) if through_timestamp.nil? || through_timestamp > note.created_at
      end
      unless @source_entity_type.to_sym == :company  # companies don't have emails
        source_entity.emails_each do |email|
          migrate_email(email)  if through_timestamp.nil? || through_timestamp > email.created_at
        end
      end
    end

    msg = "Success: #{@notes_count[:success]} notes/emails, #{@comments_count[:success]} comments / Failed: #{@notes_count[:failed]} notes/emails"
    log_migration({ source_entity_type: source_entity, target_entity_id: @current[:target_id], target_before: {}, target_after: @new_notes, message: msg})

  end

  def migrate_note(note)
    puts "[debug] migrate_note: @current[:source_id]=#{@current[:source_id]} | note=#{note.id}, #{note.created_at} "
    # only process notes where this entity is the subject
    return unless note.subject_id.to_s == @current[:source_id].to_s

    target_note = find_target_note(:note,note.id)
    return if target_note.nil?  # error scenario - abort
    return if @run.load_history? && !target_note.empty?  # don't update existing notes when just loading history
    comments = note.comments
    return unless note_updated?(note.attributes, target_note) || note_comments_updated?(comments,target_note)

    author_name = get_source_name(:user, note.author_id)

    note_txt = []
    note_txt << "[Highrise Note: Created by #{author_name} on #{format_note_dt(note.created_at)}]"
    note_txt << format_textbox(note.body)
    note_txt << get_comments(comments)
    note_txt << '' << note_tag(:note,note.id)

    target_update = {}
    target_update = {
        action: 'Highrise Note',
        comments: note_txt.join("\r\n"),
        dateAdded: format_timestamp(note.created_at),
        personReference: @target_person
    }

    migrate_note_or_email(note,target_note,target_update,author_name)

  end

  def migrate_email(email)
    puts "[debug] migrate_email: @current[:source_id]=#{@current[:source_id]} | email=#{email.id}, #{email.created_at} "
    return unless email.subject_id.to_s == @current[:source_id].to_s  # only process emails where this entity is the subject

    target_note = find_target_note(:email,email.id)
    return if target_note.nil?  # error scenario - abort
    return if @run.load_history? && !target_note.empty?  # don't update existing notes when just loading history
    comments = email.comments
    return unless note_updated?(email.attributes, target_note) || note_comments_updated?(comments,target_note)

    author_name = get_source_name(:user, email.author_id)

    note_txt = []
    note_txt << "[Highrise Email: Sent to #{email.subject_name} by #{author_name} on #{format_note_dt(email.created_at)}]"
    note_txt << "Subject: #{email.title}"
    note_txt << format_textbox(email.body)
    note_txt << get_attachments(email) if email.respond_to?(:attachments) && email.attachments.count > 0
    note_txt << get_comments(comments)
    note_txt << '' << note_tag(:email,email.id)

    target_update = {}
    target_update = {
        action: 'Highrise Email',
        comments: note_txt.join("\r\n"),
        dateAdded: format_timestamp(email.created_at),
        personReference: @target_person
    }

    migrate_note_or_email(email,target_note,target_update,author_name)
  end

  def migrate_note_or_email(note_or_email, target_note, target_update, author_name)
    puts "[debug] migrate_note_or_email: #{note_or_email.id}"
    author_obj = map_assoc(:corporate_user, 'name', author_name)
    if author_obj[:id].blank?
      log_error("Missing Author=#{author_obj} (#{note_or_email.author_id}) - applying default")
      author_obj = nil
    else
      author_obj[:_subType] = 'CorporateUser'
    end
    target_update.merge!({commentingPerson: author_obj}) unless author_obj.nil?

    target_update.merge!({jobOrder: @target_reference[:jobOrder]}) unless @target_reference[:jobOrder].nil?

    # Highrise: Notes can be attached to (aka subject) 'party' (company/person), or 'deal'
    # but Collections are only deals (we don't use cases)
    note_reference = {}
    if note_or_email.collection_type == 'Deal' && @source_entity_type != 'deal'
      job_orders = search_assoc(:job_order,'customInt1',note_or_email.collection_id)
      note_reference[:jobOrder] = { id: job_orders[0][:id]} if job_orders.count == 1
    end
    target_update.merge!({jobOrder: note_reference[:jobOrder]}) unless note_reference[:jobOrder].nil?
    update_target_note(target_note,target_update,@target_reference.merge(note_reference))

  end

  def find_target_note(note_type,note_id)
    puts "[debug] #find_target_note: #{note_tag(note_type,note_id)}"
    notes = @target.search(:note,'comments:"' + note_tag(note_type,note_id) +'"',{count: 2})
    return {} if notes.nil? || notes.empty?

    if notes.count>1
      log_error("Multiple notes found with tag '#{note_tag(note_type,note_id)}' - not updating any")
      @notes_count[:failed] = @notes_count[:failed] + 1
      return nil
    elsif notes[0].class==ServiceError
      log_error("API Error finding target note: #{notes[0].message}")
      @notes_count[:failed] = @notes_count[:failed] + 1
      return nil
    end
    notes[0]
  end

  def note_updated?(source_note,target_note)
    # return source_note[:updated_at].to_i*1000 > target_note[:dateLastModified].to_i
    # highrise doesn't actually update the timestamp when a note is edited :-(
    true
  end

  def note_comments_updated?(comments,target_note)
    updated = false
    comments.each do |comment|
      updated = comment.updated_at.to_i*1000 > target_note[:dateLastModified].to_i
      break if updated
    end
    updated
  end

  def update_target_note(current_note,new_note,note_refs)
    puts "[debug] #update_target_note new_note=#{new_note.inspect}"
    note_id = nil
    if @run.test_only?
      msg = "(test only)"
    else
      if current_note[:id].blank?
        result = @target.create(:note, new_note)
        note_id = result[:changedEntityId] if result.class == Hashie::Mash && !result[:changedEntityId].nil?
      else
        result = @target.update(:note, current_note[:id], new_note)
        note_id = current_note[:id]
      end

      if result.class == ServiceError
        log_error("Service Error for Note: #{result.message}")
        @notes_count[:failed] = @notes_count[:failed] + 1
      elsif result[:errorMessage]
        result[:errors].each {|n| log_error("API Error for Note: #{n.inspect}") } unless result[:errors].nil?
        @notes_count[:failed] = @notes_count[:failed] + 1
      elsif result[:changeType]
        @notes_count[:success] = @notes_count[:success] + 1
        @comments_count[:success] = @comments_count[:success] + @comments_count[:current_note]
        unless note_id.nil?
          @new_notes << note_id
          update_note_entities(note_id, note_refs, result[:changeType].downcase == 'insert')
        end
     else
        log_error("Update_Target_Note: Result Unknown! #{result.inspect}")
        @notes_count[:failed] = @notes_count[:failed] + 1
      end
    end
  end

  def note_tag(note_type,note_id)
    "[highrise.#{note_type.to_s.downcase}.id=#{note_id}]"
  end

  def update_note_entities(note_id,references,note_is_new)
    note_entities = {}
    unless note_is_new
      @target.get_association(:note,note_id,:entities,{fields: 'id,targetEntityID,targetEntityName'}).each do |entity|
        key = entity[:targetEntityName].to_s + ' ' + entity[:targetEntityID].to_s
        note_entities[key] = entity[:id]
      end
    end

    references.each do |ref_type, ref_obj|
      ref_update = {
          note: { id: note_id },
          targetEntityID: ref_obj[:id],
          targetEntityName: ref_type == :jobOrder ? 'JobOrder' : 'User'
      }
      if note_entities.delete(ref_update[:targetEntityID].to_s + ' ' + ref_update[:targetEntityName].to_s).nil?
        ref_result = @target.create(:note_entity,ref_update)
        if ref_result.class == ServiceError
          log_error("Service Error for NoteEntity: #{ref_result.message}")
        elsif ref_result[:errorMessage]
          ref_result[:errors].each {|n| log_error("API Error for NoteEntity: #{n.inspect}") } unless ref_result[:errors].nil?
        end
      else
        # entity already exists - nothing to do!
      end
    end

    # added all the entities we need - now delete any remaining entities
    note_entities.each do |key,id|
      puts "[debug] update_note_entities > delete id=#{id} key=#{key}"
      @target.delete(:note_entity,id)
    end
  end

  def get_comments(comments)
    @comments_count[:current_note] = 0
    comment_hx = []
    comments.each do |comment|  # assuming these are already in chrono order
      if comment_hx.empty?
        comment_hx << '' << "[Comments]"
      end
      comment_author = get_source_name(:user, comment.author_id)
      comment_hx << "[#{format_note_dt(comment.created_at)}] #{comment_author}: #{format_textbox(comment.body)}"
      @comments_count[:current_note] = @comments_count[:current_note] + 1
    end
    comment_hx
  end

  def get_attachments(email)
    note = []
    email.attachments.each do |attach|
      name = attach.respond_to?(:name) ? attach.name.downcase : ''
      unless name.blank? || name.include?(".png") || name.include?(".jpg") || name.include?(".gif")
        if note.empty?
          note << '' << "[Attachments]"
        end
        note << '<a href="' + attach.url.to_s + '">' + attach.name + '</a>'
      end
    end
    note
  end

  def migrate_task
    puts "[debug] #migrate_task id=#{@current[:source_id]}"
    return unless @current[:source_entity].done_at.nil?
    # return unless @current[:source_entity].owner_id == 872193  # DEBUG Flan only

    get_target_entity
    return if @current[:target_entity].nil?  # failed
    source_entity = @current[:source_entity]

    target_update = {}

    owner_name = get_source_name(:user, source_entity.owner_id)
    owner_obj = map_assoc(:corporate_user, 'name', owner_name)
    if owner_obj[:id].blank?
      log_error("Missing Owner=#{owner_name} (#{source_entity.owner_id}) - task not migrated")
      return
    end

    target_update.merge!({
       dateAdded: format_timestamp(source_entity.created_at),
       dateBegin: format_timestamp(source_entity.due_at),
       dateEnd: format_timestamp(source_entity.due_at),
       description: '',
       isCompleted: false,
       isDeleted: false,
       isPrivate: false,
       notificationMinutes: 30,
       owner: owner_obj,
       subject: format_str(source_entity.body,100),
       taskUUID: @current[:source_id],
       type: map_value(:type,source_entity.category_id)
    })

    ref_obj = {}
    case source_entity.subject_type.to_s.downcase
      when 'party'
        source_record = @source.get(:person,source_entity.subject_id)
        if source_record.nil?  || source_record.class == ServiceError # lookup failed - could be company?
          source_record = @source.get(:company,source_entity.subject_id)
          client_contact_obj = get_corporation_contact(source_record.name) unless source_record.nil? || source_record.empty?
          ref_obj[:clientContact] = client_contact_obj unless client_contact_obj.nil? || client_contact_obj.empty?
        else
          target_type = get_target_type(:person,source_record,true)
          record = map_assoc(target_type,'customInt1',source_entity.subject_id)
          key = target_type == :candidate ? :candidate : :clientContact
          ref_obj[key] = record unless record.nil? || record.empty?
        end
      when 'deal'
        record = map_assoc(:job_order,'customInt1',source_entity.subject_id)
        ref_obj[:jobOrder] = record unless record.nil? || record.empty?
    end

    target_update.merge!(ref_obj) unless ref_obj.empty?
    update_target(target_update)
  end

  def get_target_entity
    puts "[debug] #get_target_entity id=#{@current[:source_id]} => #{@target_entity_type}"
    # return nil if @current[:source_id].nil?
    search_field = @target_entity_type.to_sym == :task ? 'taskUUID' : 'customInt1'
    target_entities = search_assoc(@target_entity_type,search_field,@current[:source_id])
    puts "[debug] #get_target_entity: results = #{target_entities.inspect}"
    if target_entities.class == ServiceError || target_entities[0].class == ServiceError
      log_error("Error retrieving target: #{target_entities[0].message}")
      return nil
    end

    if target_entities.count == 0 && !(@run.create_record? || @run.test_only? || @run.catch_all?)
      log_error("No target record found with source ID #{@current[:source_id]} and phase is NOT 'create_record' or 'catch_all'")
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

  def get_corporation_contact(corp_name)
    puts "[debug] #get_corporation_contact: name=#{corp_name}"
    return nil if corp_name.blank?
    contact_obj = map_assoc(:client_contact, 'name',"Generic #{truncate_name(corp_name)}")
    if contact_obj.nil? || contact_obj[:id].blank?
      log_error("Missing generic contact for corp #{corp_name} - applying default")
      contact_obj = map_assoc(:client_contact,'customInt1',MappingService::DEFAULT_CONTACT)
    end
    contact_obj
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
    msg = "Exception: #{e.message}\nBacktrace:\n#{e.backtrace.join("\n").gsub(Rails.root.to_s,"")}"
    id = @current.nil? ? nil : @current[:source_id]
    @run.migration_logs.create(log_type: MigrationLog.log_types[:exception], message: msg, id_list: id)
  end

  # source_entity, target_entity_id, target_before, target_after, message
  def log_migration(v={})
    source_id = v[:source_entity_type].respond_to?(:id) ? v[:source_entity_type].id : v[:source_entity_type][:id]
    @run.migration_logs.create(log_type: MigrationLog.log_types[:mapped], source_id: source_id, source_before: v[:source_entity_type].to_json, target_id: v[:target_entity_id], target_before: v[:target_before].to_json, target_after: v[:target_after].to_json, message: v[:message])
  end

  def truncate_name(val)
    val.blank? ? '' : val.truncate(50,omission:'')
  end
  def format_phone(val)
    val.nil? ? nil : number_to_phone(val.tr('()-.– ',''))
  end

  def format_address(val)
    val.nil? || val.blank? ? nil : val.gsub("\n"," ").strip
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
    # puts "[debug] format_timestamp: val=#{val} (#{val.class})"
    return nil if val.blank?
    val = val.to_time if val.class == String
    val.to_i == 0 ? nil : val.to_i*1000
  end

  def format_note_dt(val)
    val.in_time_zone("Central Time (US & Canada)").strftime("%b %-d %Y at %I:%M %P %Z")
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
    val = val.to_i if field == 'customInt1'  # force it to int
    val = val.to_s if field == 'taskUUID'    # force to string
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
    return "Jennell Darrow" if entity == :user && id.to_i == 1081247  # fugly hack
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
    "'" + val.gsub("'","''") + "'"
  end

  def double_quote(val)
    '"' + val + '"'
  end

end