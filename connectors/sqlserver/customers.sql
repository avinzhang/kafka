-- Create the test database
CREATE DATABASE kafka;
GO
USE kafka;

-- Create some customers ...
CREATE TABLE customers (
  id INTEGER IDENTITY(1,1) NOT NULL PRIMARY KEY,
  first_name VARCHAR(25) NOT NULL,
  last_name VARCHAR(25) NOT NULL,
  update_ts DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);
INSERT INTO customers(first_name,last_name)
  VALUES ('Sally','Thomas');
GO

