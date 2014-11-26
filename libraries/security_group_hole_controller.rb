module SecurityGroupHoleController
  
  def self.awscli_command_stem(region, aws_access_key_id, aws_secret_access_key)
    command_base = ""
    if !aws_access_key_id.nil? && !aws_secret_access_key.nil?
      command_base = "AWS_ACCESS_KEY_ID=#{aws_access_key_id} AWS_SECRET_ACCESS_KEY=#{aws_secret_access_key} "
    end
    command_base << "/usr/local/bin/aws --region #{region} "
    command_base
  end
  
  def self.get_awscli_argument_for_security_group(security_group)
    security_group[/sg-([0-9a-f]{8})/, 1].nil? ? "group-name" : "group-id"
  end
  
  # private
  def self.detect_rds_hole(security_group, cidr, region, aws_access_key_id, aws_secret_access_key)
    command_base = awscli_command_stem(region, aws_access_key_id, aws_secret_access_key)
    str=%x^#{command_base} rds describe-db-security-groups --db-security-group-name #{security_group}^
    json=JSON.parse(str)
    # the return value - array of [ hole_exists, num_holes ]
    [ json['DBSecurityGroups'].first['IPRanges'].any? { | cidrHash | 
      cidrHash['CIDRIP'] == cidr && ["authorized", "authorizing"].include?(cidrHash['Status']) },
      json['DBSecurityGroups'].first['IPRanges'].size ]
  end
  
  def self.open_rds_hole_if_necessary(security_group, cidr, region, aws_access_key_id, aws_secret_access_key)
    hole_exists, num_holes = detect_rds_hole(security_group, cidr, region, aws_access_key_id, aws_secret_access_key)
    if !hole_exists
      command_base = awscli_command_stem(region, aws_access_key_id, aws_secret_access_key)
      shell = Mixlib::ShellOut.new(command_base + "rds authorize-db-security-group-ingress --db-security-group-name #{security_group} --cidrip #{cidr}")
      shell.run_command
      if shell.exitstatus != 0
        # failed to poke hole.
        Chef::Log.info("Failed to poke hole in RDS security group #{security_group} for cidr #{cidr}")
        Chef::Log.info('STDOUT: ' + shell.stdout)
        Chef::Log.info('STDERR: '+ shell.stderr)
        Chef::Log.info("There are #{num_holes} holes in the security group #{security_group}")
        false
      else
        # hole poked successfully
        Chef::Log.info("Successfully poked hole in RDS security group #{security_group} for cidr #{cidr}")
        Chef::Log.info("There are now #{num_holes+1} holes in the security group #{security_group}")
        true
      end
    else
      # hole already exists
      Chef::Log.info("Hole in RDS security group #{security_group} for cidr #{cidr} already exists among #{num_holes} holes")
      true
    end
  end
  
  def self.close_rds_hole_if_necessary(security_group, cidr, region, aws_access_key_id, aws_secret_access_key)
    hole_exists, num_holes = detect_rds_hole(security_group, cidr, region, aws_access_key_id, aws_secret_access_key)
    if hole_exists
      command_base = awscli_command_stem(region, aws_access_key_id, aws_secret_access_key)
      shell = Mixlib::ShellOut.new(command_base + "rds revoke-db-security-group-ingress --db-security-group-name #{security_group} --cidrip #{cidr}")
      shell.run_command
      if shell.exitstatus != 0
        # failed to plug hole
        Chef::Log.info("Failed to plug hole in RDS security group #{security_group} for cidr #{cidr}")
        Chef::Log.info('STDOUT: ' + shell.stdout)
        Chef::Log.info('STDERR: '+ shell.stderr)
        Chef::Log.info("There are #{num_holes} holes in the security group #{security_group}")
        false
      else
        # plugged hole
        Chef::Log.info("Successfully plugged hole in RDS security group #{security_group} for cidr #{cidr}")
        Chef::Log.info("There are now #{num_holes-1} holes in the security group #{security_group}")
        true
      end
    else
      # no hole in this security group
      Chef::Log.info("Hole in RDS security group #{security_group} for cidr #{cidr} is not present among #{num_holes} holes")
      true
    end
  end
end
