ALTER TABLE inventory.flight
ADD CONSTRAINT chk_available_seats_positive CHECK (available_seats > 0);
