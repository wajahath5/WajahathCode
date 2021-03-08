#!/bin/bash 

############### START DESCRIPTION #################
# Script Purpose : Install Web and App Components on CentOS 7 
# 
#
#
# Exit States
# 0 - SUCCESS
# 1 - Executed by Non-Root User / if user input is missing
# 2 - Script Failure
############### END DESCRIPTION ###################

### Global Variables
LOG=/tmp/stack.log 
rm -f $LOG
R="\e[31m"
RB="\e[1;31m"
N="\e[0m"
YB="\e[1;33m"
GB="\e[1;32m"
C="\e[36m"
MB="\e[1;35m"
APPUSER="student"

DBUSER=student
DBPASS=student1
DBHOST=RDSHOST 
DBNAME=studentapp

DBCON="<Resource name='jdbc/TestDB' auth='Container' type='javax.sql.DataSource' maxTotal='100' maxIdle='30' maxWaitMillis='10000'  username='${DBUSER}' password='${DBPASS}' driverClassName='com.mysql.jdbc.Driver' url='jdbc:mysql://${DBHOST}:3306/${DBNAME}'/>"

### Functions

## This function is to proint an error message
Error() {
  #echo -e "\t\t\t${YB}>>>>>>>>>>>>>>>ERROR<<<<<<<<<<<<<<<<${N}"
  #echo -e "${R}$1${N}"
  echo -e "${C}$(date +%F-%T) ${MB}$COMPONENT${N} ${RB}ERROR:${N} $1"
}

Success() {
  echo -e "${C}$(date +%F-%T) ${MB}$COMPONENT${N} ${GB}SUCCESS:${N} $1"
}

Head() {
  echo -e "\n\t\t\t${YB}>>>>>>>>>>>>>>  $COMPONENT SETUP  <<<<<<<<<<<<<<<<<${N}\n"
}

Status_Check() {
  case $1 in 
    0) 
      Success "$2" 
      ;;
    *) 
      Error "$2"
      echo -e "\t Refer Logfile : $LOG for error\n"
      exit 2 
      ;;
  esac
}

### Main Program



## Check whether the user running the script is a root user or not 
USER_ID=$(id -u)
if [ "$USER_ID" -ne 0  ]; then 
  Error "You should be a root user to execute this script"
  exit 1
fi 

### Config Web Server 
COMPONENT=WEBSERVER
Head  ## TO print heading 
yum install httpd -y &>>$LOG
Status_Check $? "Installing Web Server"

echo 'ProxyPass "/student" "http://localhost:8080/student"
ProxyPassReverse "/student"  "http://localhost:8080/student"' >/etc/httpd/conf.d/app-proxy.conf  
Status_Check $? "Setup Application Proxy Config"

curl -s https://s3-us-west-2.amazonaws.com/studentapi-cit/index.html -o /var/www/html/index.html &>>$LOG 
Status_Check $? "Setup Default Application Web Page"

systemctl enable httpd &>/dev/null 
systemctl restart httpd &>>$LOG 
Status_Check $? "Start Web Server"


### Config App Server 
COMPONENT=APPSERVER
Head # To print heading 
yum install java -y &>>$LOG 
Status_Check $? "Install Java"

id $APPUSER &>>$LOG 
if [ $? -eq 0 ]; then   
  Status_Check "0" "Add Application User"
else 
  useradd $APPUSER &>>$LOG 
  Status_Check "$?" "Add Application User"
fi 

TOMCAT_VERSION=$(curl -s "https://archive.apache.org/dist/tomcat/tomcat-8/?C=M;O=D" | grep DIR -w | head -1 |xargs -n1 | awk -F '/' '/^href/ {print $1}' |awk -F '=v' '{print $2}')
TOMCAT_HOME=/home/$APPUSER/apache-tomcat-${TOMCAT_VERSION}

cd /home/$APPUSER
wget -qO- https://archive.apache.org/dist/tomcat/tomcat-8/v${TOMCAT_VERSION}/bin/apache-tomcat-${TOMCAT_VERSION}.tar.gz | tar -xz 
Status_Check "$?" "Download Application Server"

cd $TOMCAT_HOME 
curl -s -o webapps/student.war https://s3-us-west-2.amazonaws.com/studentapi-cit/student.war &>>$LOG 
Status_Check "$?" "Download Student Application"

curl -s -o lib/mysql-connector.jar https://s3-us-west-2.amazonaws.com/studentapi-cit/mysql-connector.jar &>>$LOG 
Status_Check "$?" "Download Tomcat JDBC Driver"

chown $APPUSER:$APPUSER $TOMCAT_HOME -R 

sed -i -e "$ i $DBCON" $TOMCAT_HOME/conf/context.xml &>>$LOG 
Status_Check "$?" "Configuring DB Connection"

curl -s https://s3-us-west-2.amazonaws.com/studentapi-cit/tomcat-init -o /etc/init.d/tomcat &>>$LOG 
Status_Check "$?" "Configure Tomcat Startup Script"

chmod +x /etc/init.d/tomcat 
systemctl daemon-reload 

systemctl restart tomcat 
Status_Check "$?" "Starting Tomcat Service"

echo 

