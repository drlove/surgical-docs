require 'clipboard'
require 'date'

class HealthStatus
  # make a look-up of health conditions to a standard form
  @@HealthCond = Hash.new
  @@HealthCond = {
    "htn"      => "blood pressure",
    "diabetes type 2" => "diabetes",
    "ckd" => "low kidney function",
    "gerd" => "acid reflux",
    "bph" => "enlarged prostate",
    "atrial fib" => "afib"
  }
  # lists of meds for common health conditions
  @@CondMeds = Hash.new
  @@CondMeds = {
    "acid reflux" => ["omeprazole", "pantoprazole"],
    "afib" => ["apixaban", "carvedilol", "coumadin",
                              "metoprolol", "propafenone"],
    "diabetes" => ["empagliflozin", "metformin"],
    "enlarged prostate" => ["finasteride", "tamsulosin"],
    "blood pressure" => ["amlodipine", "bisoprolol",
                              "carvedilol", "hydrochlorothiazide",
                              "irbesartan", "metoprolol", "olmesartan",
                              "telmisartan","valsartan", "verapamil"],
  }

  # make a look-up from generic to brand drug names
  @@MedGeneric = Hash.new
  @@MedGeneric = {
    "apixaban"      => "eliquis",
    "atorvastatin"  => "lipitor",
    "coumadin"      => "warfarin",
    "empagliflozin" => "jardiance",
    "pantoprazole"  => "pantoloc",
    "rosuvastatin"  => "crestor",
    "salbutamol"    => "ventolin",
    "tamsulosin"    => "flomax"
  }
  # make a reverse look-up from brand to generic drug names
  @@MedBrand = Hash.new
  @@MedGeneric.each do |key, value|
    @@MedBrand[value] = key
  end

  # initialize report
  def initialize(my_input)
    @LabValues = Hash.new
    @Meds = Hash.new
    @Conditions = Hash.new
    @Allergies = Array.new
    @FamilyHx = Array.new
    @Lifestyle = Hash.new
    @Prevent = Hash.new
    @actionplan = Array.new
    @outtext = ""
    @labname = ""
    parse_status(my_input);
  end

  # parse line of medication
  def med_parse(name, line)
    # all lower case
    name = name.downcase
    line = line.downcase
    # remove brand prefix
    if name =~ /\w+-(\w+)/
      name = $1
    end
    # switch to generic name if this is a brand name
    if @@MedBrand.key?(name)
      name = @@MedBrand[name]
    end

    # find the medication route
    route = "oral"
    if line =~ /\blotion\b|\bcream\b|\bgel\b|\bointment\b/
      route = "topical"
    end
    if line =~ /\binhaler\b/
      route = "inhaled"
    end
    if line =~ /\[im:|\bvial\b/
      route = "injected"
    end

    # add to the list of meds
    # note that we do not have an indication yet
    indication = ""
    @Meds[name] = [route, indication];
    puts "Found med: #{name}  (#{route})"
  end

  # parse line of active medication
  def med_act_parse(line)
    return unless line =~ /^\w\w\w \d\d, \d\d\d\d\s+([\w-]+)/
    med_parse($1, line)
  end

  # parse line of external medication
  def med_ext_parse(line)
    return unless line =~ /^Unknown\s+([\w-]+)/
    med_parse($1, line)
  end

  def med_indication_attach(med, indication)
    if @Meds.key?(med)
      if @Meds[med][1] == ""
        @Meds[med][1] = indication
      else
        @Meds[med][1] += ", #{indication}"
      end
    end
  end

  # try to match existing conditions to medications
  def med_indication_find()
    # go through all conditions
    @Conditions.each do |key, value|
      # if list of meds available for this condition
      if @@CondMeds.key?(key)
        @@CondMeds[key].each { |med| med_indication_attach(med,key) }
      end
    end
  end

  # Add single med to output stream  
  def med_single_dump(name)
    route = @Meds[name][0];
    indication = @Meds[name][1];
    if indication != ""
      indication = "for #{indication}"
    end
    # do not print oral as a route
    if route == "oral"
      route = ""
    end
    brand = ""
    if @@MedGeneric.key?(name)
      brand = @@MedGeneric[name]
      # enclose brand name in parantheses
      brand = "(#{brand})"
    end

    fout = sprintf("%s %s %s %s", name.ljust(20), route.ljust(10),
                   brand.ljust(15), indication)
    out_add(fout);
  end

  # Add med list to output stream
  def med_dump()
    oralmeds = Array.new
    inhaledmeds = Array.new
    topicalmeds = Array.new
    injectedmeds = Array.new

    # separate into routes
    @Meds.each do |key, value|
      if value[0] == "oral"
        oralmeds.push(key)
      elsif value[0] == "inhaled"
        inhaledmeds.push(key)
      elsif value[0] == "topical"
        topicalmeds.push(key)
      elsif value[0] == "injected"
        injectedmeds.push(key)
      end
    end
    # sort into alphabetical order within routes
    oralmeds.sort!
    inhaledmeds.sort!
    topicalmeds.sort!
    injectedmeds.sort!

    # if more than 5 oral meds, potential polypharmacy
    if oralmeds.length > 5
      num = oralmeds.length
      action_add("Consider reducing number of medications. Currently #{num} oral medications")
    end

    out_add("")
    out_add("Medications")
    out_add_line()

    # now add a line for every med
    oralmeds.each { |name| med_single_dump name }
    injectedmeds.each { |name| med_single_dump name }
    inhaledmeds.each { |name| med_single_dump name }
    topicalmeds.each { |name| med_single_dump name }
  end

  def mhx_dump()
    out_add("")
    out_add("Medical History")
    out_add_line()
    @Conditions.keys.sort.each do |key|
      fout = sprintf("%s %s", key.ljust(20), @Conditions[key])
      out_add(fout)
    end
  end

  def mhx_parse(line)
    return unless line =~ /^([^-]+)-(.+)$/
    name = $1.strip.downcase
    # map to a standard name if available
    if @@HealthCond.key?(name)
      nname = @@HealthCond[name]
      puts "Mapped #{name} to #{nname}"
      name = nname
    end
    @Conditions[name] = $2
    puts "Found history: #{name}  (#{$2})"
  end

  def allergy_dump()
    out_add("")
    out_add("Allergies")
    out_add_line()
    @Allergies.each { |x| out_add(x) }
  end

  def allergy_parse(line)
    return unless line =~ /^\w\w\w \d\d, \d\d\d\d\s+(.+)\z/
    @Allergies << $1
  end

  def lifestyle_dump()
    out_add("")
    out_add("Lifestyle")
    out_add_line()
    @Lifestyle.each do |key, value|
      fout = sprintf("%s %s", key.ljust(20), value[1])
      out_add(fout)
      date = value[0]
      due_date = date >> 12
      if @date > due_date
        action_add("Yearly update for #{key} overdue. Last #{date}")
      end
    end
  end

  def lifestyle_parse(line)
    return unless line =~ /^(\w\w\w \d\d, \d\d\d\d)\s+(\w+)\s+-\s+(.+)\z/
    date = Date.parse $1
    @Lifestyle[$2] = [date, $3]
  end

  def famhx_dump()
    out_add("")
    out_add("Family History")
    out_add_line()
    @FamilyHx.each { |x| out_add(x) }
  end

  def famhx_parse(line)
    @FamilyHx << line
  end

  def prevent_parse(line)
    return unless line =~ /^(\w\w\w \d\d, \d\d\d\d)\s+(\w+.*)\z/
    date = Date.parse $1
    remainder = $2

    puts "Remainder is (#{remainder})"
    # keep track of repeat interval in months
    # 0 means no repeat
    months = 0
    if remainder =~ /repeat in (\d+)\s+(\w+)/
      puts "Matched (#{$1}) and (#{$2})"
      months = $1.to_i
      if $2 =~ /year/
        months *= 12
      end
    end
    puts "Months is #{months}"
    if remainder =~ /Fibroscan/
      item = "Fatty Liver Scan"
      months = 36 unless months > 0
    end
    if remainder =~ /Influenza/
      item = "Flu Vaccine"
      months = 12 unless months > 0
    end
    if remainder =~ /Colonoscopy/
      item = "Colonoscopy"
      months = 120 unless months > 0
    end
    if remainder =~ /FIT/
      item = "Colon Cancer Screen (FIT)"
      months = 24 unless months > 0
    end
    if remainder =~ /Mammo/
      item = "Breast Cancer Screen (Mammogram)"
      months = 24 unless months > 0
    end
    if remainder =~ /PAP/
      item = "Cervical Cancer Screen (PAP)"
      months = 36 unless months > 0
    end
    @Prevent[item] = [date, months]
  end

  # lab values are kept in hash of arrays
  # each item of the array is an array:
  # [value, date]
  def lab_add(name, value, date)
    puts "Adding Lab: #{name} #{value} #{date}"
    if !@LabValues.key?(name)
      @LabValues[name] = Array.new
    end
    @LabValues[name] << [value, date]
  end

  # labs are added in reverse chronically order
  # so index 0 is the most recent
  # index 1 is the second most recent and so on
  # if the index doesn't exist, will return ""
  def lab_get(name, index)
    retval = ""
    if @LabValues.key?(name)
      if !@LabValues[name][index].nil?
        retval = @LabValues[name][index][0]
      end
    end
    return retval
  end

  def lab_date_get(name, index)
    retval = ""
    if @LabValues.key?(name)
      if !@LabValues[name][index].nil?
        retval = @LabValues[name][index][1]
      end
    end
    return retval
  end

  # generate a table of most recent lab values
  # with a maximum number of columns specified
  def lab_table(names, columns)
    cur_index = Array.new
    dates = Array.new
    table = Hash.new
    cur_col = 0
    empty = 0

    # start at the most recent entry for all
    names.each_with_index { |val, index| cur_index[index] = 0 }

    # keep collecting values until the columns
    # filled or no more data
    while ((cur_col < columns) && (empty == 0))

      # find the next most recent date out of all
      # note that if an entry doesn't exist it
      # will return ""
      cur_index.each_with_index {|val, index|
        dates[index] = lab_date_get(names[index], val)}

      latest = ""
      dates.each_with_index {|val, index|
        if latest == ""
          latest = val
          latest_index = index
        elsif val != ""
          if val > latest
            latest = val
            latest_index = index
          end
        end
      }
      # if latest date is still empty, must mean
      # no data left.
      if latest == ""
        empty = 1
      else
        # otherwise add a column for the next date
        table[latest] = Array.new
        # find all the values available for this date
        # for the next column in the table
        dates.each_with_index {|val, index|
          labval = ""
          if (val == latest)
            labval = lab_get(names[index],cur_index[index])
            cur_index[index] += 1
          end
          table[latest][index] = labval
        }
        cur_col += 1
      end
    end

    # print out the table
    # print out the dates
    row = ""
    table.keys.sort.each do |key|
      date = key.strftime('%b %Y')
      row = sprintf("%-20s%-10s",row,date)
    end
    out_add(row)

    # then print the values for each lab
    names.each_with_index { |val, index|
      row = val
      table.keys.sort.each do |key|
        value = table[key]
        row = sprintf("%-20s%-10s",row,value[index])
      end
      out_add(row)
    }
  end

  def lab_dump
    @LabValues.each do |key, value|
      puts "Key is #{key}"
      @LabValues[key].each { |x| puts x }
    end
  end

  # parse lab values section
  def lab_parse(line)
    # lab names appear on a separate line followed by a colon
    if line =~ /^([-\w\s]+):/
      @labname = $1
    end
    if line =~ /^([\.\d]+).*\s(\w\w\w \d\d, \d\d\d\d)\z/
      value = $1
      date = Date.parse $2
      if @labname == ""
        puts "Got lab value #{value} and date #{date} but no lab name"
      else
        lab_add(@labname, value, date)
      end
    end
  end

  def parse_status(my_input)
    section = ""
    my_input.each_line do |line|
      line = line.strip
      case line
      when /^Active Medications:/
        section = "Meds"
        next
      when /^External Medications:/
        section = "EMeds"
        next
      when /^Surgical\/Medical History:/
        section = "MHx"
        next
      when /^Known Allergies:/
        section = "Allergies"
        next
      when /^Lifestyle Notes:/
        section = "Lifestyle"
        next
      when /^Family History:/
        section = "FamHx"
        next
      when /^Accuro to Accuro Summary Entries:/
        section = "Ignore"
        next
      when /^Preventative Screening:/
        section = "Prevent"
        next
      when /^Screening:/
        section = "Ignore"
        next
      when /^Laboratory Values:/
        section = "Labs"
        next
      end

      case section
      when "Meds"
        med_act_parse(line)
        next
      when "EMeds"
        med_ext_parse(line)
        next
      when "MHx"
        mhx_parse(line)
        next
      when "Allergies"
        allergy_parse(line)
        next
      when "Lifestyle"
        lifestyle_parse(line)
        next
      when "FamHx"
        famhx_parse(line)
        next
      when "Ignore"
        next
      when "Prevent"
        prevent_parse(line)
        next
      when "Labs"
        lab_parse(line)
        next
      else
        if line =~ /^Health Status Update/
          @date  = line[/\bDate:\s+(\w\w\w \d\d, \d\d\d\d)/, 1]
          @date = Date.parse @date
          puts "Date is #{@date}"
        elsif line =~ /^Age:/
          @age  = line[/\b(\d+)\z/, 1]
          puts "Age is #{@age}"
        elsif line =~ /^Sex at Birth:/
          @sex  = line[/\b(\w+)\z/, 1]
          puts "Sex is #{@sex}"
        end
      end
    end
    # try to find indications for the medications
    med_indication_find
  end

  def out_add(line)
    if line.length > 75
      line = "#{line[0...71]}..."
    end
    @outtext << "#{line}\n"
  end
  
  def out_add_line()
    out_add("----------------------------------------------------------------------")
  end

  # add to the action plan
  def action_add(line)
    @actionplan << "#{line}"
  end

  # dump the action plan
  def action_dump()
    out_add("")
    out_add("Action Plan")
    out_add_line()
    @actionplan.each { |line| out_add(line) }
  end

  # return formatted conversion of kg to lb
  def kg_to_lb kg
    lbs = (kg.to_f / 0.45459237).round(0)
    return "#{lbs} lbs"
  end

  # return formatted conversion of cm to ft in
  def cm_to_ft cm
    inches = cm.to_f * 0.39370079
    feet = (inches/12).floor
    inches = (inches - feet*12).round
    return "#{feet}ft #{inches}in"
  end

  # BMI calculation
  def bmi_calc(kg, cm)
    return (kg.to_f / (cm.to_f / 100)**2).round(1)
  end
  # Calculate a weight (kg) for a given height and BMI
  def bmi_reverse_calc(cm, bmi)
    return (bmi * (cm.to_f / 100)**2).round(1)
  end

  # Height, Weight, and BMI section
  def bmi_dump()
    cur_ht_cm = lab_get("Height",0)
    cur_wt_kg = lab_get("Weight",0)
    cur_date  = lab_date_get("Weight",0)
    cur_date  = cur_date.strftime('%b %Y')

    cur_ht_ft = cm_to_ft(cur_ht_cm)
    cur_wt_lbs = kg_to_lb(cur_wt_kg)
    cur_bmi = bmi_calc(cur_wt_kg, cur_ht_cm)

    prev_ht_cm = lab_get("Height",1)
    prev_wt_kg = lab_get("Weight",1)
    prev_date  = lab_date_get("Weight",1)
    prev_date  = prev_date.strftime('%b %Y')

    prev_bmi = bmi_calc(prev_wt_kg, prev_ht_cm)

    diff_ht = cur_ht_cm.to_i - prev_ht_cm.to_i
    diff_wt = cur_wt_kg.to_i - prev_wt_kg.to_i
    diff_bmi = cur_bmi.to_i - prev_bmi.to_i

    ht_dir = "you gained"
    if diff_ht < 0
      ht_dir = "you lost"
      diff_ht = diff_ht.abs
    end
    diff_ht = "#{ht_dir} #{diff_ht} cm"

    wt_dir = "you gained"
    if diff_wt < 0
      wt_dir = "you lost"
      diff_wt = diff_wt.abs
    end
    diff_wt_lbs = kg_to_lb(diff_wt)
    diff_wt = "#{wt_dir} #{diff_wt} kg (#{diff_wt_lbs})"

    cur_ht = "#{cur_ht_cm} cm (#{cur_ht_ft})"
    cur_wt = "#{cur_wt_kg} kg (#{cur_wt_lbs})"

    if cur_bmi < 18.5
      bmi_class = "Underweight (below 18.5)"
    elsif cur_bmi < 25
      bmi_class = "Normal (18.5-24.9)"
    elsif cur_bmi < 30
      bmi_class = "Overweight (25-29.9)"
    else
      bmi_class = "Obese (30 or above)"
    end
    if cur_bmi > 25
      action_add("Consider weight management (current BMI #{cur_bmi})")
    end

    # calculate BMI cutoff weights
    wt_min_kg = bmi_reverse_calc(cur_ht_cm, 18.5)
    wt_max_kg = bmi_reverse_calc(cur_ht_cm, 24.9)
    wt_obese_kg = bmi_reverse_calc(cur_ht_cm, 29.9)
    wt_min_lbs = kg_to_lb(wt_min_kg)
    wt_max_lbs = kg_to_lb(wt_max_kg)
    wt_obese_lbs = kg_to_lb(wt_obese_kg)
    wt_range = "#{wt_min_kg} kg - #{wt_max_kg} kg (#{wt_min_lbs} - #{wt_max_lbs})"
    wt_obese = "#{wt_obese_kg} kg (#{wt_obese_lbs})"

    out_add("")
    out_add("Body Mass Index (BMI) Analysis")
    out_add_line()
    out_add("Latest #{cur_date} Height: #{cur_ht}  Weight: #{cur_wt}")
    out_add("Compared to #{prev_date} #{diff_ht} and #{diff_wt}")
    out_add("Current BMI at #{cur_bmi} is classified as #{bmi_class}")
    out_add("Your normal BMI weight range is #{wt_range}")
    out_add("Your obese BMI weight range is over #{wt_obese}")
    out_add("")

    lab_table(["Height", "Weight"],5)
  end

  def diabetes_dump()
    out_add("")
    out_add("Diabetes Analysis")
    out_add_line()
    lab_table(["Hemoglobin A1C", "Fasting Glucose"],5)
  end

  def cholesterol_dump()
    out_add("")
    out_add("Cholesterol Analysis")
    out_add_line()
    lab_table(["HDL", "LDL", "Total Cholesterol", "Non-HDL Cholesterol"],5)
  end

  def bloodpressure_dump()
    out_add("")
    out_add("Blood Pressure Analysis")
    out_add_line()
    lab_table(["SBP", "DBP"],5)
  end

  def kidney_dump()
    out_add("")
    out_add("Kidney Function Analysis")
    out_add_line()
    lab_table(["eGFR", "ACR", "Urine RBC"],5)
  end

  def liver_dump()
    out_add("")
    out_add("Liver Function Analysis")
    out_add_line()
    lab_table(["ALT", "AST", "ALP", "GGT"],5)
  end

  def prostate_dump()
    out_add("")
    out_add("Prostate Analysis")
    out_add_line()
    lab_table(["PSA"],5)
  end

  # generate the output report
  # at this point all the data has been read
  # we can now analyze, summarize, and make recommendations
  def report_dump()
    curdate = @date.strftime('%b %d, %Y')
    out_add("Health Status Update and Plan                            #{curdate}")
    out_add_line()
    out_add("Age: #{@age}")
    out_add("Sex at Birth: #{@sex}")
    allergy_dump
    mhx_dump
    med_dump
    lifestyle_dump
    famhx_dump
    bmi_dump

    diabetes_dump
    cholesterol_dump
    bloodpressure_dump
    kidney_dump
    liver_dump
    prostate_dump

    # lab_dump
    action_dump
    return @outtext
  end
end

status = HealthStatus.new(Clipboard.paste)
report = status.report_dump

Clipboard.copy(report)
