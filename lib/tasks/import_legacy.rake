require 'csv'

namespace :import do

  desc "candidate name check"
  task :name_check,[:file, :dest_sys] => :environment do |t,args|
    dest_sys = System.find(args.dest_sys)
    unless dest_sys && dest_sys.integration_type.to_sym == :bullhorn
      puts "[ERROR] - Invalid destination system: #{args.dest_sys}"
      exit
    end

    candidate_processed = {}

    run = MigrationRun.new({
                               destination_system: dest_sys,
                               entity_type: :placement,
                               phase: MigrationRun.phases[:create_record],
                               status: MigrationRun.statuses[:running]
                           })
    run.save

    puts "[debug] Run created: #{run.id}"

    CSV.open( "tmp/results.csv", 'w' ) do |writer|
      CSV.foreach(args.file, headers: true, :encoding => 'windows-1251:utf-8') do |row|
        row_hash = row.to_hash

        candidate_name = row_hash["candidate"]
        msg = ""
        unless candidate_processed[candidate_name] == 1
          candidate_processed[candidate_name] = 1

          target_entities = search_assoc(run,:candidate,'name',candidate_name)

          if target_entities.class == ServiceError || target_entities[0].class == ServiceError
            msg = "Error retrieving candidate: #{target_entities[0].message}"
          end

          if target_entities.count == 0
            msg = "No target candidate found with name #{candidate_name} "
          end

          if target_entities.count > 1
            msg = "Multiple target candidates found with name #{candidate_name}"
          end

          if target_entities.count == 1
            msg = "Unique Candidate found: #{target_entities[0][:id]}"
          end

          writer << [candidate_name, msg]
         end
      end
    end
  end

  desc "legacy placements"
  task :legacy_placements,[:file, :dest_sys] => :environment do |t,args|

    dest_sys = System.find(args.dest_sys)
    unless dest_sys && dest_sys.integration_type.to_sym == :bullhorn
      puts "[ERROR] - Invalid destination system: #{args.dest_sys}"
      exit
    end

    run = MigrationRun.new({
                             destination_system: dest_sys,
                             entity_type: :placement,
                             phase: MigrationRun.phases[:create_record],
                             status: MigrationRun.statuses[:running]
                           })
    run.save

    puts "[debug] Run created: #{run.id}"
    # Create a placement record for each legacy deal
    CSV.foreach(args.file, headers: true, :encoding => 'windows-1251:utf-8') do |row|
      row_hash = row.to_hash

      target_job_obj = find_job(run,row_hash["hr_deal_id"])
      puts "[debug] target_job_obj: #{target_job_obj.inspect}"
      # error out if job not found

      candidate_obj = find_candidate(run,row_hash["candidate"])
      puts "[debug] candidate_obj: #{candidate_obj.inspect}"
      # error out if candidate not found

      # not needed
      #contact_obj = find_contact(run,target_job_obj)


      # Now create target_placement from this job
      if target_job_obj && candidate_obj
        target_placement = {}
        target_placement.merge!({
                            jobOrder: target_job_obj,
                            candidate: candidate_obj,
                            status: "Completed",
                            salary: row_hash["salary"] || 0,
                            fee: row_hash["fee"] || 0,
                            flatFee: row_hash["flatFee"],
                            clientBillRate: row_hash["clientBillRate"],
                            payRate: row_hash["payRate"],
                            customBillRate1: row_hash["customBillRate1"],
                            customPayRate1: row_hash["customPayRate1"],
                            clientOvertimeRate: row_hash["clientOvertimeRate"],
                            overtimeRate: row_hash["overtimeRate"],
                            customBillRate2: row_hash["customBillRate2"],
                            customPayRate2: row_hash["customPayRate2"],
                            salaryUnit: row_hash["salaryUnit"],
                            costCenter: row_hash["costCenter"],
                            employeeType: row_hash["employeeType"],
                            employmentType: row_hash["employmentType"],
                            dateBegin: format_timestamp(row_hash["dateBegin"]),
                            dateEffective: format_timestamp(row_hash["dateBegin"]),
                            dateClientEffective: format_timestamp(row_hash["dateBegin"]),
                            dateEnd: format_timestamp(row_hash["dateEnd"]),
                            customInt1: row_hash["customInt1"],
                            customText5: row_hash["customText5"],
                            billingFrequency: row_hash["billingFrequency"],
                            customText8: row_hash["customText8"],
                            customText6: row_hash["customText6"],
                            customText7: row_hash["customText7"],
                            daysGuaranteed: row_hash["daysGuaranteed"] || 0,
                            comments: "Legacy placement conversion: #{row_hash["jobOrder.id"]}"
                                })
        result = create_placement(run,target_placement)
      end

    end

  end
end

def format_timestamp(val)
  # puts "[debug] format_timestamp: val=#{val} (#{val.class})"
  return nil if val.blank? || val == '1900-01-00'
  val = val.to_time if val.class == String
  val.to_i == 0 ? nil : val.to_i*1000
end


def find_job(run, job_identifier)
  puts "[debug] find_job [hr_deal_id]: #{job_identifier}"

  target_entities = search_assoc(run,:job_order,'customInt1',job_identifier)

  if target_entities.class == ServiceError || target_entities[0].class == ServiceError
    log_error(run,"Error retrieving job: #{target_entities[0].message}")
    return nil
  end

  if target_entities.count == 0
    log_error(run,"No target job found with source ID #{job_identifier} ")
    return nil
  end

  if target_entities.count > 1
    log_error(run,"Multiple target jobs found with source ID #{job_identifier}")
    return nil
  end

  {id: target_entities[0][:id]}

end

def find_contact(run, job_obj)
  puts "[debug] find_contact [job_obj]: #{job_obj}"

  job = run.destination_system.get(:job_order,job_obj[:id])
  name = "Generic #{job[:clientCorporation][:name]}" unless job.nil? || job[:clientCorporation].nil?

  target_entities = search_assoc(run,:client_contact,'name',name)

  if target_entities.nil?
    log_error(run,"Invalid search for client_contact! [job] #{job.inspect}")
    return nil
  end

  if target_entities.class == ServiceError || target_entities[0].class == ServiceError
    log_error(run,"Error retrieving contact: #{target_entities[0].message}")
    return nil
  end

  if target_entities.count == 0
    log_error(run,"No generic contact found with name #{name} ")
    return nil
  end

  if target_entities.count > 1
    log_error(run,"Multiple contacts found with name #{name}")
    return nil
  end

  {id: target_entities[0][:id]}
end

def find_candidate(run, candidate_name)
  puts "[debug] find_candidate: #{candidate_name}"
  target_entities = search_assoc(run,:candidate,'name',candidate_name)

  if target_entities.class == ServiceError || target_entities[0].class == ServiceError
    log_error(run,"Error retrieving candidate: #{target_entities[0].message}")
    return nil
  end

  if target_entities.count == 0
    log_error(run,"No target candidate found with name #{candidate_name} ")
    return nil
  end

  if target_entities.count > 1
    log_error(run,"Multiple target candidates found with name #{candidate_name}")
    return nil
  end

  {id: target_entities[0][:id]}

end

def search_assoc(run,entity,field,val)
  return nil if val.blank?
  val = val.to_i if field == 'customInt1'  # force it to int
  val = val.to_s if field == 'taskUUID'    # force to string
  if entity == :candidate
    qval = val.class == String ? double_quote(val) : val
    query = "#{field.to_s}:#{qval} AND isDeleted:0"
  else
    qval = val.class == String ? single_quote(val) : val
    query = "#{field.to_s}=#{qval}"
  end
  run.destination_system.search(entity,query)
end

def single_quote(val)
  "'" + val.gsub("'","''") + "'"
end

def double_quote(val)
  '"' + val + '"'
end


def create_placement(run, attribs)
  puts "[debug] create_placement"
  ret_obj = {}
  result = run.destination_system.create(:placement,attribs)
  ret_obj[:id] = result[:changedEntityId] if result.class == Hashie::Mash && !result[:changedEntityId].nil?

  if result.class == ServiceError
    msg = result.message
  elsif result[:errorMessage]
    # log_error("API Error: #{result.inspect}")
    result[:errors].each {|n| log_error(run,"API Error: #{n.inspect}") } unless result[:errors].nil?
    msg = 'Target save failed: ' + result[:errorMessage] + '; ' + ( result[:errors].nil? ? '' : (result[:errors].map {|n| n.inspect}).join('; ') )
  elsif result[:changeType]
    msg = "Target record #{result[:changeType].downcase}'d"
  else
    msg = 'Unknown result'
  end

  puts "[debug] #{msg}"
  ret_obj[:message] = msg
  run.migration_logs.create(log_type: MigrationLog.log_types[:mapped], source_id: nil, source_before: ''.to_json, target_id: ret_obj[:id], target_before: ''.to_json, target_after: attribs.to_json, message: msg)

  ret_obj
end

def log_error(run,msg)
  puts "[debug] error: #{msg}"
  log = run.migration_logs.create(log_type: MigrationLog.log_types[:error], message: msg)
end
