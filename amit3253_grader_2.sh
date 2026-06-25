import boto3
import sys
import urllib.request
import urllib.error
import ssl
import time

# --- CONFIGURATION ---
ssl_context = ssl._create_unverified_context()

# Global Score Keepers
TOTAL_MARKS = 0
SCORED_MARKS = 0

def print_header(title):
    print(f"\n{'='*60}")
    print(f" {title}")
    print(f"{'='*60}")

# Updated Helper to handle Partial Marks
def grade_step(description, max_points, status, details=""):
    global TOTAL_MARKS, SCORED_MARKS
    TOTAL_MARKS += max_points
    
    if status == "PASS":
        SCORED_MARKS += max_points
        print(f"[\u2713] PASS (+{max_points}): {description}")
    elif status == "PARTIAL":
        # partial is usually half marks or custom. Here we assume logic passed the specific partial score in 'max_points'
        # BUT to keep function signature simple, we will handle point calculation outside or use a tuple?
        # Let's simplify: The Caller decides the points awarded.
        pass 
    else:
        print(f"[X] FAIL (0/{max_points}): {description}")
        if details:
            print(f"    -> Issue: {details}")

# New Flexible Grader Function
def award_points(description, max_points, points_earned, details=""):
    global TOTAL_MARKS, SCORED_MARKS
    TOTAL_MARKS += max_points
    SCORED_MARKS += points_earned
    
    if points_earned == max_points:
        print(f"[\u2713] PASS (+{points_earned}/{max_points}): {description}")
    elif points_earned > 0:
        print(f"[!] PARTIAL (+{points_earned}/{max_points}): {description}")
        if details:
            print(f"    -> Note: {details}")
    else:
        print(f"[X] FAIL (0/{max_points}): {description}")
        if details:
            print(f"    -> Issue: {details}")

def check_website_detailed(url, keyword):
    try:
        headers = {'User-Agent': 'Mozilla/5.0'}
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, timeout=3, context=ssl_context) as response:
            if response.status == 200:
                content = response.read().decode('utf-8')
                content_clean = content.lower().replace(" ", "")
                keyword_clean = keyword.lower().replace(" ", "")
                is_loaded = True
                is_name_found = keyword_clean in content_clean
                return is_loaded, is_name_found, "Page loaded successfully"
            else:
                return False, False, f"HTTP Status: {response.status}"
    except Exception as e:
        return False, False, str(e)

def main():
    print_header("AMIT3253 CLOUD COMPUTING - AUTO GRADER (V8 - PARTIAL MARKS)")
    
    session = boto3.session.Session()
    region = session.region_name
    print(f"Scanning Region: {region}")
    
    student_name_input = input("Enter Student Full Name: ").strip().lower()
    student_name_nospace = student_name_input.replace(" ", "")
    print(f"Looking for resources containing: '{student_name_nospace}'...")

    ec2 = boto3.client('ec2')
    asg_client = boto3.client('autoscaling')
    elbv2 = boto3.client('elbv2')
    rds = boto3.client('rds')

    # =========================================================
    # TASK 1: EC2 WEB SERVER DEPLOYMENT (25 MARKS)
    # =========================================================
    print_header("Task 1: EC2 Web Server Deployment (25%)")
    
    target_inst = None
    try:
        # 1. Check EC2 Instance (5 Marks)
        instances = ec2.describe_instances(Filters=[{'Name': 'instance-state-name', 'Values': ['running']}])
        all_instances = [i for r in instances['Reservations'] for i in r['Instances']]
        
        if all_instances:
            target_inst = all_instances[0] 
            for inst in all_instances:
                for tag in inst.get('Tags', []):
                    if tag['Key'] == 'Name' and student_name_nospace in tag['Value'].lower().replace(" ", ""):
                        target_inst = inst
                        break
        
        if target_inst:
            inst_name = next((tag['Value'] for tag in target_inst.get('Tags', []) if tag['Key'] == 'Name'), "Unknown")
            award_points("EC2 Instance Launched & Running", 5, 5, f"ID: {target_inst['InstanceId']}")
            
            # 2. Instance Type - PARTIAL LOGIC (5 Marks)
            itype = target_inst['InstanceType']
            if itype == 't3.small':
                award_points("Instance Type (t3.small)", 5, 5)
            elif itype in ['t3.medium', 't3.micro', 't2.micro']:
                award_points("Instance Type (t3.small)", 5, 2, f"Wrong type used: {itype} (Awarded 2/5)")
            else:
                award_points("Instance Type (t3.small)", 5, 0, f"Incorrect type: {itype}")
            
            # 3. Security Groups - PARTIAL LOGIC (5 Marks)
            sg_ids = [sg['GroupId'] for sg in target_inst.get('SecurityGroups', [])]
            has_ssh = False
            has_http = False
            if sg_ids:
                sgs = ec2.describe_security_groups(GroupIds=sg_ids)['SecurityGroups']
                for sg in sgs:
                    for perm in sg.get('IpPermissions', []):
                        ip_proto = perm.get('IpProtocol')
                        if ip_proto == '-1':
                            has_ssh, has_http = True, True
                        elif ip_proto == 'tcp':
                            fp, tp = perm.get('FromPort'), perm.get('ToPort')
                            if fp and tp:
                                if fp <= 22 and tp >= 22: has_ssh = True
                                if fp <= 80 and tp >= 80: has_http = True
            
            if has_ssh and has_http:
                award_points("Security Group: Ports 22 & 80", 5, 5)
            elif has_ssh or has_http:
                found = "SSH" if has_ssh else "HTTP"
                award_points("Security Group: Ports 22 & 80", 5, 3, f"Only {found} open. Missing one port.")
            else:
                award_points("Security Group: Ports 22 & 80", 5, 0)

            # 4. Web Access (5 Marks) & Name (5 Marks)
            public_ip = target_inst.get('PublicIpAddress')
            if public_ip:
                print(f"    Testing EC2 Public IP: http://{public_ip}")
                is_loaded, is_name_found, msg = check_website_detailed(f"http://{public_ip}", student_name_input)
                award_points("Website Accessible (HTTP 200)", 5, 5 if is_loaded else 0, msg)
                award_points("Website Shows Student Name", 5, 5 if is_name_found else 0)
            else:
                award_points("Website Accessible (HTTP 200)", 5, 0, "No Public IP")
                award_points("Website Shows Student Name", 5, 0, "No Public IP")
        else:
            award_points("EC2 Instance Launched & Running", 5, 0, "No running instances found")
            award_points("Instance Type (t3.small)", 5, 0)
            award_points("Security Group: Ports 22 & 80", 5, 0)
            award_points("Website Accessible (HTTP 200)", 5, 0)
            award_points("Website Shows Student Name", 5, 0)
            
    except Exception as e:
        print(f"Error Task 1: {e}")

    # =========================================================
    # TASK 2: LAUNCH TEMPLATE & ASG (25 MARKS)
    # =========================================================
    print_header("Task 2: Launch Template & ASG (25%)")
    
    try:
        # 1. LT Found
        lts = ec2.describe_launch_templates()['LaunchTemplates']
        target_lt = next((lt for lt in lts if "lt-" in lt['LaunchTemplateName']), None)
        if target_lt:
            award_points("Launch Template Found (lt-*)", 5, 5, target_lt['LaunchTemplateName'])
            # 2. LT User Data
            lt_vers = ec2.describe_launch_template_versions(LaunchTemplateId=target_lt['LaunchTemplateId'], Versions=['$Latest'])
            if 'UserData' in lt_vers['LaunchTemplateVersions'][0]['LaunchTemplateData']:
                 award_points("LT includes User Data", 5, 5)
            else:
                 award_points("LT includes User Data", 5, 0)
        else:
            award_points("Launch Template Found (lt-*)", 5, 0)
            award_points("LT includes User Data", 5, 0)

        # 3. ASG Found & Linked
        asgs = asg_client.describe_auto_scaling_groups()['AutoScalingGroups']
        target_asg = next((a for a in asgs if "asg-" in a['AutoScalingGroupName']), None)
        if target_asg:
            lt_linked = False
            if 'LaunchTemplate' in target_asg and target_lt:
                if target_asg['LaunchTemplate']['LaunchTemplateName'] == target_lt['LaunchTemplateName']:
                    lt_linked = True
            award_points("ASG Created & Linked", 5, 5 if lt_linked else 0)
            
            # 4. Scaling Config
            c_min, c_max, c_des = target_asg['MinSize'], target_asg['MaxSize'], target_asg['DesiredCapacity']
            if c_min == 1 and c_max == 3 and c_des == 1:
                award_points("Scaling Config (1-3-1)", 5, 5)
            else:
                award_points("Scaling Config (1-3-1)", 5, 0, f"Found {c_min}-{c_max}-{c_des}")
            
            # 5. ASG Instances
            if len(target_asg['Instances']) >= 1:
                award_points("Instances Running via ASG", 5, 5)
            else:
                award_points("Instances Running via ASG", 5, 0)
        else:
            award_points("ASG Created & Linked", 5, 0)
            award_points("Scaling Config (1-3-1)", 5, 0)
            award_points("Instances Running via ASG", 5, 0)

    except Exception as e:
        print(f"Error Task 2: {e}")

    # =========================================================
    # TASK 3: LOAD BALANCER (25 MARKS)
    # =========================================================
    print_header("Task 3: Load Balancer (25%)")
    alb_dns = None
    try:
        # 1. ALB Exists
        albs = elbv2.describe_load_balancers()['LoadBalancers']
        target_alb = next((alb for alb in albs if "alb-" in alb['LoadBalancerName']), None)
        if target_alb:
            award_points("ALB Created & Internet-Facing", 5, 5 if target_alb['Scheme'] == 'internet-facing' else 0)
            alb_dns = target_alb['DNSName']
            alb_arn = target_alb['LoadBalancerArn']
            
            # 2. Listener
            listeners = elbv2.describe_listeners(LoadBalancerArn=alb_arn)['Listeners']
            has_80 = any(l['Port'] == 80 and l['Protocol'] == 'HTTP' for l in listeners)
            award_points("Listener Configured (HTTP:80)", 5, 5 if has_80 else 0)
        else:
            award_points("ALB Created & Internet-Facing", 5, 0)
            award_points("Listener Configured (HTTP:80)", 5, 0)

        # 3. Target Group
        tgs = elbv2.describe_target_groups()['TargetGroups']
        target_tg = next((tg for tg in tgs if "tg-" in tg['TargetGroupName']), None)
        if target_tg:
            award_points("Target Group Exists", 5, 5)
            # 4. Health Checks - PARTIAL LOGIC
            health = elbv2.describe_target_health(TargetGroupArn=target_tg['TargetGroupArn'])
            healthy_count = sum(1 for t in health['TargetHealthDescriptions'] if t['TargetHealth']['State'] == 'healthy')
            if healthy_count >= 1:
                award_points("Targets Registered & Healthy", 5, 5)
            else:
                # Partial mark for creating TG but failing health checks
                award_points("Targets Registered & Healthy", 5, 2, "TG exists but instances unhealthy")
        else:
            award_points("Target Group Exists", 5, 0)
            award_points("Targets Registered & Healthy", 5, 0)

        # 5. DNS Access
        if alb_dns:
            print(f"    Testing ALB: http://{alb_dns}")
            is_loaded, is_name_found, msg = check_website_detailed(f"http://{alb_dns}", student_name_input)
            award_points("ALB DNS Access & Name Verify", 5, 5 if is_name_found else 0, msg)
        else:
            award_points("ALB DNS Access & Name Verify", 5, 0)
            
    except Exception as e:
        print(f"Error Task 3: {e}")

    # =========================================================
    # TASK 4: RDS DATABASE INSTANCE (25 MARKS)
    # =========================================================
    print_header("Task 4: RDS Database Instance (25%)")
    try:
        db_instances = rds.describe_db_instances()['DBInstances']
        expected_identifier = f"rds-{student_name_nospace}"
        target_db = next((db for db in db_instances if db['DBInstanceIdentifier'].lower() == expected_identifier), None)
        if not target_db:
            target_db = next((db for db in db_instances if db['DBInstanceIdentifier'].lower().startswith("rds-") and student_name_nospace in db['DBInstanceIdentifier'].lower()), None)
        if not target_db:
            target_db = next((db for db in db_instances if db['DBInstanceIdentifier'].lower().startswith("rds-")), None)
        if not target_db:
            target_db = db_instances[0] if db_instances else None

        if target_db:
            db_id = target_db['DBInstanceIdentifier']
            db_id_lower = db_id.lower()
            if db_id_lower == expected_identifier:
                id_points = 5
                id_note = db_id
            elif db_id_lower.startswith("rds-") and student_name_nospace in db_id_lower:
                id_points = 4
                id_note = f"Expected {expected_identifier}, found {db_id}"
            elif db_id_lower.startswith("rds-"):
                id_points = 3
                id_note = f"Expected {expected_identifier}, found {db_id}"
            else:
                id_points = 2
                id_note = f"RDS exists but identifier should be {expected_identifier}; found {db_id}"
            award_points("RDS Instance Identifier (rds-<yourname>)", 5, id_points, id_note)

            engine_points = 0
            engine_notes = []
            if target_db.get('Engine', '').lower() == 'mysql':
                engine_points += 2
            else:
                engine_notes.append(f"Engine: {target_db.get('Engine', 'Unknown')}")
            if target_db.get('DBInstanceClass') == 'db.t3.micro':
                engine_points += 3
            else:
                engine_notes.append(f"Class: {target_db.get('DBInstanceClass', 'Unknown')}")
            award_points("Engine MySQL and Class db.t3.micro", 5, engine_points, "; ".join(engine_notes))

            config_points = 0
            config_notes = []
            if target_db.get('AllocatedStorage') == 10:
                config_points += 2
            else:
                config_notes.append(f"Storage: {target_db.get('AllocatedStorage', 'Unknown')} GB")
            if target_db.get('StorageType') == 'gp2':
                config_points += 1
            else:
                config_notes.append(f"Storage type: {target_db.get('StorageType', 'Unknown')}")
            if target_db.get('DBName') == 'studentdb':
                config_points += 1
            else:
                config_notes.append(f"DB name: {target_db.get('DBName', 'Not shown/Unknown')}")
            if target_db.get('MasterUsername') == 'admin':
                config_points += 1
            else:
                config_notes.append(f"Master username: {target_db.get('MasterUsername', 'Unknown')}")
            award_points("Storage 20GB gp2, DB studentdb, Username admin", 5, config_points, "; ".join(config_notes))

            access_points = 0
            access_notes = []
            if target_db.get('DBInstanceStatus') == 'available':
                access_points += 2
            else:
                access_notes.append(f"Status: {target_db.get('DBInstanceStatus', 'Unknown')}")
            if target_db.get('PubliclyAccessible') is False:
                access_points += 2
            else:
                access_notes.append("Public access is enabled")
            if target_db.get('MonitoringInterval', 0) == 0:
                access_points += 1
            else:
                access_notes.append(f"Enhanced monitoring interval: {target_db.get('MonitoringInterval')} seconds")
            award_points("Available, Private, Enhanced Monitoring Disabled", 5, access_points, "; ".join(access_notes))

            sg_ids = [sg['VpcSecurityGroupId'] for sg in target_db.get('VpcSecurityGroups', [])]
            mysql_rule_found = False
            if sg_ids:
                security_groups = ec2.describe_security_groups(GroupIds=sg_ids)['SecurityGroups']
                for sg in security_groups:
                    for perm in sg.get('IpPermissions', []):
                        from_port = perm.get('FromPort')
                        to_port = perm.get('ToPort')
                        protocol = perm.get('IpProtocol')
                        cidrs = [r.get('CidrIp') for r in perm.get('IpRanges', [])]
                        if protocol == 'tcp' and from_port is not None and to_port is not None and from_port <= 3306 <= to_port and '10.0.0.0/16' in cidrs:
                            mysql_rule_found = True
                            break
                    if mysql_rule_found:
                        break
            award_points("Security Group Allows MySQL/Aurora 3306 from 10.0.0.0/16", 5, 5 if mysql_rule_found else 0, ", ".join(sg_ids) if sg_ids else "No security groups attached")
        else:
            award_points("RDS Instance Identifier (rds-<yourname>)", 5, 0)
            award_points("Engine MySQL and Class db.t3.micro", 5, 0)
            award_points("Storage 20GB gp2, DB studentdb, Username admin", 5, 0)
            award_points("Available, Private, Enhanced Monitoring Disabled", 5, 0)
            award_points("Security Group Allows MySQL/Aurora 3306 from 10.0.0.0/16", 5, 0)
    except Exception as e:
        print(f"Error Task 4: {e}")

    print_header("FINAL RESULT")
    print(f"TOTAL SCORE: {SCORED_MARKS} / 100")

if __name__ == "__main__":
    main()