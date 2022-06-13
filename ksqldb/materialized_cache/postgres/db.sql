CREATE TABLE orders (order_id INT,
                      order_total_usd DECIMAL(5,2),
                      item VARCHAR(50),
                      cancelled_ind BOOLEAN,
                      update_ts TIMESTAMP DEFAULT CURRENT_TIMESTAMP );


CREATE FUNCTION public.update_updated_at_column() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
  BEGIN
    NEW.update_ts = NOW();
    RETURN NEW;
  END;
$$;

CREATE TRIGGER customers_updated_at_modtime BEFORE UPDATE ON orders FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column();


INSERT INTO orders VALUES (1,12.34,'Cake',false);
INSERT INTO orders VALUES (2,56.78,'More Cake',true);
INSERT INTO orders VALUES (3,910.11,'Franzbrötchen',false);
