-- Create all required empty autopilot databases
-- How to: 
  -- pgAdmin: Run each line one by one to create the databases
  -- psql: Run the script

create database autopilot_dev with encoding 'UTF8';
create database autopilot_test with encoding 'UTF8';
create database autopilot_prod with encoding 'UTF8';
create database autopilot_check with encoding 'UTF8';
create database autopilot_shadow with encoding 'UTF8';
create database autopilot_build with encoding 'UTF8';
