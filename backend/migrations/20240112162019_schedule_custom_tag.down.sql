-- Add down migration script here
ALTER TABLE schedule DROP COLUMN tag;
