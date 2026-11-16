-- =============================================================================
-- HỆ THỐNG QUẢN LÝ THƯ VIỆN SỐ THÔNG MINH - TRƯỜNG ĐH GIAO THÔNG VẬN TẢI (UTC)
-- Học phần: Phân tích Thiết kế Hướng đối tượng | GVHD: TS. Đào Thị Lệ Thủy
-- Cơ sở dữ liệu: PostgreSQL 16+ | Mức chuẩn hóa: 3NF / BCNF (14 Bảng)
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- 1. Bảng ROLES (Vai trò phân quyền RBAC)
CREATE TABLE roles (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code            VARCHAR(30) NOT NULL UNIQUE CHECK (code IN ('ADMIN', 'LIBRARIAN', 'READER')),
    name            VARCHAR(100) NOT NULL,
    permissions     JSONB NOT NULL DEFAULT '[]'::jsonb,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 2. Bảng USERS (Tài khoản xác thực hệ thống)
CREATE TABLE users (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    role_id         UUID NOT NULL REFERENCES roles(id) ON UPDATE CASCADE,
    username        VARCHAR(50) NOT NULL UNIQUE,
    email           VARCHAR(120) NOT NULL UNIQUE,
    password_hash   VARCHAR(255) NOT NULL,
    status          VARCHAR(20) NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'LOCKED', 'INACTIVE')),
    last_login_at   TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 3. Bảng MEMBERS (Hồ sơ Thẻ bạn đọc - Aggregate Root)
CREATE TABLE members (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    member_code         VARCHAR(25) NOT NULL UNIQUE,
    full_name           VARCHAR(120) NOT NULL,
    faculty             VARCHAR(120),
    member_type         VARCHAR(20) NOT NULL CHECK (member_type IN ('STUDENT', 'POSTGRAD', 'LECTURER')),
    card_expiry_date    DATE NOT NULL,
    active_loans_count  INT NOT NULL DEFAULT 0 CHECK (active_loans_count >= 0),
    unpaid_fine_balance NUMERIC(12, 2) NOT NULL DEFAULT 0.00 CHECK (unpaid_fine_balance >= 0),
    status              VARCHAR(20) NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'SUSPENDED', 'EXPIRED')),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 4. Bảng CATEGORIES (Khung phân loại thập phân Dewey - DDC)
CREATE TABLE categories (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ddc_code        VARCHAR(20) NOT NULL UNIQUE,
    name            VARCHAR(150) NOT NULL,
    parent_id       UUID REFERENCES categories(id) ON DELETE SET NULL,
    description     TEXT
);

-- 5. Bảng PUBLISHERS (Nhà xuất bản)
CREATE TABLE publishers (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name            VARCHAR(180) NOT NULL UNIQUE,
    address         VARCHAR(255),
    email           VARCHAR(120),
    website         VARCHAR(180)
);

-- 6. Bảng AUTHORS (Tác giả)
CREATE TABLE authors (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    full_name       VARCHAR(150) NOT NULL,
    orcid           VARCHAR(30) UNIQUE,
    biography       TEXT
);

-- 7. Bảng BOOK_TITLES (Đầu sách / Ấn phẩm biên mục - Aggregate Root)
CREATE TABLE book_titles (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    isbn                VARCHAR(20) NOT NULL UNIQUE,
    title               VARCHAR(300) NOT NULL,
    edition             VARCHAR(50),
    publish_year        INT NOT NULL CHECK (publish_year BETWEEN 1900 AND 2100),
    language            VARCHAR(30) NOT NULL DEFAULT 'Tiếng Việt',
    page_count          INT CHECK (page_count > 0),
    category_id         UUID NOT NULL REFERENCES categories(id),
    publisher_id        UUID NOT NULL REFERENCES publishers(id),
    cover_url           VARCHAR(500),
    ebook_url           VARCHAR(500),
    total_copies        INT NOT NULL DEFAULT 0 CHECK (total_copies >= 0),
    available_copies    INT NOT NULL DEFAULT 0 CHECK (available_copies >= 0 AND available_copies <= total_copies),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 8. Bảng trung gian BOOK_AUTHORS (Quan hệ N-M Đầu sách - Tác giả)
CREATE TABLE book_authors (
    book_title_id   UUID NOT NULL REFERENCES book_titles(id) ON DELETE CASCADE,
    author_id       UUID NOT NULL REFERENCES authors(id) ON DELETE CASCADE,
    is_primary      BOOLEAN NOT NULL DEFAULT TRUE,
    author_order    SMALLINT NOT NULL DEFAULT 1,
    PRIMARY KEY (book_title_id, author_id)
);

-- 9. Bảng BOOK_COPIES (Bản sao sách vật lý có Barcode & RFID)
CREATE TABLE book_copies (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    book_title_id   UUID NOT NULL REFERENCES book_titles(id) ON DELETE RESTRICT,
    barcode         VARCHAR(40) NOT NULL UNIQUE,
    rfid_tag        VARCHAR(64) UNIQUE,
    shelf_location  VARCHAR(50) NOT NULL,
    condition       VARCHAR(20) NOT NULL DEFAULT 'GOOD' CHECK (condition IN ('GOOD', 'MINOR_WEAR', 'DAMAGED', 'LOST')),
    price           NUMERIC(12, 2) NOT NULL CHECK (price >= 0),
    status          VARCHAR(20) NOT NULL DEFAULT 'AVAILABLE'
                    CHECK (status IN ('ACQUIRING', 'CATALOGED', 'AVAILABLE', 'BORROWED', 'RESERVED', 'MAINTENANCE', 'LOST', 'RETIRED')),
    acquired_date   DATE NOT NULL DEFAULT CURRENT_DATE
);

-- 10. Bảng RESERVATIONS (Hàng đợi đặt chỗ trước FIFO)
CREATE TABLE reservations (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reservation_code    VARCHAR(30) NOT NULL UNIQUE,
    member_id           UUID NOT NULL REFERENCES members(id),
    book_title_id       UUID NOT NULL REFERENCES book_titles(id),
    assigned_copy_id    UUID REFERENCES book_copies(id),
    queue_position      INT NOT NULL CHECK (queue_position >= 1),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    hold_expires_at     TIMESTAMPTZ,
    status              VARCHAR(25) NOT NULL DEFAULT 'PENDING'
                        CHECK (status IN ('PENDING', 'READY_FOR_PICKUP', 'FULFILLED', 'CANCELLED', 'EXPIRED'))
);

-- 11. Bảng LOANS (Phiếu mượn sách - Aggregate Root với Optimistic Locking)
CREATE TABLE loans (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    loan_code       VARCHAR(30) NOT NULL UNIQUE,
    member_id       UUID NOT NULL REFERENCES members(id),
    librarian_id    UUID NOT NULL REFERENCES users(id),
    borrowed_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    due_date        DATE NOT NULL,
    closed_at       TIMESTAMPTZ,
    renewal_count   SMALLINT NOT NULL DEFAULT 0 CHECK (renewal_count >= 0),
    status          VARCHAR(25) NOT NULL DEFAULT 'ACTIVE'
                    CHECK (status IN ('DRAFT', 'ACTIVE', 'RENEWED', 'PARTIALLY_RETURNED', 'OVERDUE', 'FINE_PENDING', 'CLOSED', 'CANCELLED')),
    version         BIGINT NOT NULL DEFAULT 0,
    CONSTRAINT chk_loan_dates CHECK (due_date >= borrowed_at::date)
);

-- 12. Bảng LOAN_ITEMS (Chi tiết từng bản sao sách trong phiếu mượn)
CREATE TABLE loan_items (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    loan_id         UUID NOT NULL REFERENCES loans(id) ON DELETE CASCADE,
    book_copy_id    UUID NOT NULL REFERENCES book_copies(id),
    returned_at     TIMESTAMPTZ,
    condition_out   VARCHAR(20) NOT NULL DEFAULT 'GOOD',
    condition_in    VARCHAR(20),
    overdue_days    INT NOT NULL DEFAULT 0 CHECK (overdue_days >= 0),
    item_status     VARCHAR(20) NOT NULL DEFAULT 'BORROWED'
                    CHECK (item_status IN ('BORROWED', 'RETURNED', 'OVERDUE', 'LOST')),
    UNIQUE (loan_id, book_copy_id)
);

-- 13. Bảng FINE_INVOICES (Hóa đơn phạt quá hạn / hư hỏng - Aggregate Root)
CREATE TABLE fine_invoices (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    invoice_code    VARCHAR(30) NOT NULL UNIQUE,
    loan_id         UUID NOT NULL REFERENCES loans(id),
    member_id       UUID NOT NULL REFERENCES members(id),
    reason          VARCHAR(30) NOT NULL CHECK (reason IN ('OVERDUE', 'DAMAGED', 'LOST_BOOK')),
    amount          NUMERIC(12, 2) NOT NULL CHECK (amount > 0),
    paid_amount     NUMERIC(12, 2) NOT NULL DEFAULT 0.00 CHECK (paid_amount >= 0 AND paid_amount <= amount),
    status          VARCHAR(20) NOT NULL DEFAULT 'UNPAID' CHECK (status IN ('UNPAID', 'PARTIALLY_PAID', 'PAID', 'WAIVED')),
    issued_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 14. Bảng PAYMENTS (Giao dịch thanh toán tiền mặt / VietQR)
CREATE TABLE payments (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    fine_invoice_id     UUID NOT NULL REFERENCES fine_invoices(id) ON DELETE RESTRICT,
    transaction_ref     VARCHAR(64) NOT NULL UNIQUE,
    method              VARCHAR(20) NOT NULL CHECK (method IN ('VIETQR', 'VNPAY', 'CASH')),
    amount              NUMERIC(12, 2) NOT NULL CHECK (amount > 0),
    paid_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    status              VARCHAR(20) NOT NULL DEFAULT 'COMPLETED' CHECK (status IN ('PENDING', 'COMPLETED', 'FAILED'))
);

-- INDEXES TỐI ƯU HIỆU NĂNG TRUY VẤN OPAC & LƯU THÔNG
CREATE INDEX idx_book_titles_trgm ON book_titles USING gin (title gin_trgm_ops);
CREATE INDEX idx_book_titles_category ON book_titles(category_id);
CREATE INDEX idx_book_copies_status_title ON book_copies(book_title_id, status);
CREATE INDEX idx_loans_member_status ON loans(member_id, status);
CREATE INDEX idx_loans_due_date_overdue ON loans(due_date) WHERE status IN ('ACTIVE', 'RENEWED');
CREATE INDEX idx_reservations_queue ON reservations(book_title_id, status, queue_position);
