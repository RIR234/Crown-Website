-- Server-authoritative demo task catalog.
-- The client-supplied title and amount are intentionally ignored by the RPC.
-- This remains a demo-credit system only; it does not process real payments.

CREATE TABLE IF NOT EXISTS public.crown_demo_task_catalog (
  task_index integer PRIMARY KEY CHECK (task_index BETWEEN 0 AND 49),
  task_title text NOT NULL,
  amount numeric(14,2) NOT NULL CHECK (amount > 0),
  active boolean NOT NULL DEFAULT true,
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.crown_demo_task_catalog ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.crown_demo_task_catalog FROM PUBLIC, anon, authenticated;

INSERT INTO public.crown_demo_task_catalog(task_index, task_title, amount)
VALUES
(0, 'Wireless Earbuds', 800.00),
(1, 'Smart Watch', 1000.00),
(2, 'Phone Case', 1200.00),
(3, 'USB-C Charger', 1500.00),
(4, 'Water Bottle', 1800.00),
(5, 'Bluetooth Speaker', 2200.00),
(6, 'Travel Backpack', 2500.00),
(7, 'Running Shoes', 3000.00),
(8, 'Smart Desk Lamp', 3500.00),
(9, 'Power Bank', 4000.00),
(10, 'Fitness Band', 4500.00),
(11, 'Travel Trolley', 5000.00),
(12, 'Mechanical Keyboard', 6000.00),
(13, 'Laptop', 7000.00),
(14, 'Smartphone', 8000.00),
(15, 'Digital Camera', 9000.00),
(16, 'Tablet', 10000.00),
(17, 'Gaming Monitor', 12000.00),
(18, 'Office Chair', 15000.00),
(19, 'Electric Scooter', 18000.00),
(20, 'Premium Watch', 22000.00),
(21, 'Drone Camera', 25000.00),
(22, 'Home Projector', 30000.00),
(23, 'Motorcycle', 35000.00),
(24, 'Studio Apartment Booking', 40000.00),
(25, 'Gaming Laptop', 50000.00),
(26, 'Professional Camera', 60000.00),
(27, 'Electric Bike', 75000.00),
(28, 'Luxury Sofa Set', 90000.00),
(29, 'Commercial Refrigerator', 100000.00),
(30, 'Designer Furniture Set', 125000.00),
(31, 'Premium Smartphone', 150000.00),
(32, 'Smart TV 75-inch', 180000.00),
(33, 'Home Renovation Package', 200000.00),
(34, 'Business Office Suite', 250000.00),
(35, 'Family Car', 300000.00),
(36, 'Premium Apartment Booking', 350000.00),
(37, 'SUV Pre-booking', 400000.00),
(38, 'Luxury Sedan', 500000.00),
(39, 'Penthouse Reservation', 600000.00),
(40, 'Commercial Property Booking', 750000.00),
(41, 'Electric Car', 900000.00),
(42, 'Villa Reservation', 1000000.00),
(43, 'Premium Motorcycle', 1200000.00),
(44, 'Office Building Suite', 1500000.00),
(45, 'Luxury Furniture Package', 1800000.00),
(46, 'High-end Workstation', 2000000.00),
(47, 'Warehouse Lease Package', 2500000.00),
(48, 'Resort Villa Booking', 3000000.00),
(49, 'Premium Real Estate Package', 4000000.00)
ON CONFLICT (task_index) DO UPDATE
SET task_title = EXCLUDED.task_title,
    amount = EXCLUDED.amount,
    active = true,
    updated_at = now();

CREATE OR REPLACE FUNCTION public.place_crown_demo_order(
  p_task_index integer,
  p_task_title text,
  p_amount numeric
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_balance numeric(14,2);
  v_order public.crown_demo_orders%ROWTYPE;
  v_task public.crown_demo_task_catalog%ROWTYPE;
  v_next integer;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF p_task_index IS NULL OR p_task_index < 0 OR p_task_index > 49 THEN
    RAISE EXCEPTION 'Invalid demo order';
  END IF;

  SELECT * INTO v_task
  FROM public.crown_demo_task_catalog
  WHERE task_index = p_task_index AND active = true;
  IF NOT FOUND THEN RAISE EXCEPTION 'Task is unavailable'; END IF;

  INSERT INTO public.crown_demo_wallets(user_id) VALUES (v_uid)
  ON CONFLICT (user_id) DO NOTHING;
  PERFORM 1 FROM public.crown_demo_wallets WHERE user_id = v_uid FOR UPDATE;
  SELECT balance INTO v_balance FROM public.crown_demo_wallets WHERE user_id = v_uid;

  SELECT COALESCE(max(task_index) + 1, 0) INTO v_next
  FROM public.crown_demo_orders
  WHERE user_id = v_uid AND status = 'confirmed';
  IF p_task_index <> v_next THEN RAISE EXCEPTION 'Complete the previous task first'; END IF;
  IF v_balance < v_task.amount THEN RAISE EXCEPTION 'Insufficient demo balance'; END IF;

  UPDATE public.crown_demo_wallets
  SET balance = balance - v_task.amount,
      total_spent = total_spent + v_task.amount,
      updated_at = now()
  WHERE user_id = v_uid;

  INSERT INTO public.crown_demo_orders(user_id, task_index, task_title, amount)
  VALUES (v_uid, v_task.task_index, v_task.task_title, v_task.amount)
  RETURNING * INTO v_order;

  INSERT INTO public.crown_demo_transactions(user_id, order_id, type, amount, note)
  VALUES (v_uid, v_order.id, 'demo_order', v_task.amount, 'Demo order confirmed');

  RETURN jsonb_build_object(
    'order_id', v_order.id,
    'balance', v_balance - v_task.amount,
    'spent', (SELECT total_spent FROM public.crown_demo_wallets WHERE user_id = v_uid),
    'task_index', v_task.task_index,
    'task_title', v_task.task_title,
    'amount', v_task.amount
  );
END;
$$;

REVOKE ALL ON FUNCTION public.place_crown_demo_order(integer,text,numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.place_crown_demo_order(integer,text,numeric) TO authenticated;
