# E-commerce API — PRD

Backend API for a small e-commerce platform.

## Features

### F1: User Authentication
OAuth2 login with Google. JWT tokens for session management.
- POST /auth/google — exchange Google token for JWT
- POST /auth/refresh — refresh expired JWT
- Acceptance: JWT expires in 24h
- Acceptance: invalid/expired tokens return 401

### F2: Product Catalog
CRUD operations for products.
- GET /products — list all products (paginated, 20/page)
- GET /products/:id — single product
- POST /products — create (admin only)
- Acceptance: search by name via ?q= query param
- Acceptance: non-admin POST returns 403

### F3: Shopping Cart
Per-user cart, persisted in Redis.
- GET /cart — current user's cart
- POST /cart/items — add item with quantity
- DELETE /cart/items/:product_id — remove item
- Acceptance: cart clears after successful checkout
- Acceptance: adding same product twice increments quantity

### F4: Checkout
Process cart into an order.
- POST /checkout — create order from cart, clear cart
- Returns order ID and total
- Acceptance: insufficient stock returns 409
- Acceptance: empty cart returns 400
