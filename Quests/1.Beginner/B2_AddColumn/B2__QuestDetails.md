**Scenario**:
The `customers.customer` table needs a new column to track the date when a customer joined the loyalty program.

**Objective**:
Add a column `join_date` of type `DATE` to the `customers.customer` table.

**Hints**:
- Look up the `ALTER TABLE` statement for adding columns.
- Ensure the column is nullable initially if existing rows don't have values.

Test your migration script by running it locally and confirming the schema change.