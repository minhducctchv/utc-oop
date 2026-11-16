-- HỆ THỐNG QUẢN LÝ THƯ VIỆN (UTC LibMS) - CSDL QUAN HỆ CHUẨN 3NF (9 BẢNG GỌN RÕ)
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username VARCHAR(50) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    role VARCHAR(20) NOT NULL CHECK (role IN ('ADMIN', 'LIBRARIAN', 'READER'))
);

CREATE TABLE members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    member_code VARCHAR(25) NOT NULL UNIQUE,
    full_name VARCHAR(120) NOT NULL,
    member_type VARCHAR(20) NOT NULL CHECK (member_type IN ('STUDENT', 'LECTURER')),
    status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE'
);

CREATE TABLE categories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code VARCHAR(20) NOT NULL UNIQUE,
    name VARCHAR(120) NOT NULL
);

CREATE TABLE book_titles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    isbn VARCHAR(20) NOT NULL UNIQUE,
    title VARCHAR(250) NOT NULL,
    author VARCHAR(150) NOT NULL,
    category_id UUID NOT NULL REFERENCES categories(id),
    available_count INT NOT NULL DEFAULT 0 CHECK (available_count >= 0)
);

CREATE TABLE book_copies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    book_title_id UUID NOT NULL REFERENCES book_titles(id),
    barcode VARCHAR(40) NOT NULL UNIQUE,
    shelf VARCHAR(50) NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'AVAILABLE'
           CHECK (status IN ('AVAILABLE', 'BORROWED', 'RESERVED', 'MAINTENANCE'))
);

CREATE TABLE reservations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id UUID NOT NULL REFERENCES members(id),
    book_title_id UUID NOT NULL REFERENCES book_titles(id),
    queue_order INT NOT NULL CHECK (queue_order >= 1),
    hold_until TIMESTAMPTZ,
    status VARCHAR(20) NOT NULL DEFAULT 'PENDING'
);

CREATE TABLE loans (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    loan_code VARCHAR(30) NOT NULL UNIQUE,
    member_id UUID NOT NULL REFERENCES members(id),
    borrow_date DATE NOT NULL DEFAULT CURRENT_DATE,
    due_date DATE NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE'
);

CREATE TABLE loan_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    loan_id UUID NOT NULL REFERENCES loans(id) ON DELETE CASCADE,
    book_copy_id UUID NOT NULL REFERENCES book_copies(id),
    return_date DATE,
    UNIQUE (loan_id, book_copy_id)
);

CREATE TABLE fines (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    loan_id UUID NOT NULL UNIQUE REFERENCES loans(id),
    amount NUMERIC(12,2) NOT NULL CHECK (amount > 0),
    reason VARCHAR(50) NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'UNPAID' CHECK (status IN ('UNPAID', 'PAID'))
);
