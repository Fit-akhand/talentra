
BEGIN;

CREATE TABLE profile.candidate_document (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    candidate_profile_id BIGINT NOT NULL,

    document_type VARCHAR(30) NOT NULL DEFAULT 'resume',
    document_status VARCHAR(20) NOT NULL DEFAULT 'uploaded',

    original_filename VARCHAR(255) NOT NULL,
    storage_provider VARCHAR(30) NOT NULL,
    storage_key VARCHAR(1024) NOT NULL,

    mime_type VARCHAR(100) NOT NULL,
    file_size_bytes BIGINT NOT NULL,
    checksum_sha256 CHAR(64),

    is_primary BOOLEAN NOT NULL DEFAULT FALSE,

    uploaded_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    processed_at TIMESTAMPTZ,
    archived_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_candidate_document PRIMARY KEY (id),

    CONSTRAINT fk_candidate_document_candidate_profile
        FOREIGN KEY (candidate_profile_id)
        REFERENCES profile.candidate_profile (id)
        ON UPDATE RESTRICT ON DELETE CASCADE,

    CONSTRAINT uq_candidate_document_storage_reference
        UNIQUE (storage_provider, storage_key),

    CONSTRAINT ck_candidate_document_type
        CHECK (
            document_type IN (
                'resume',
                'cover_letter',
                'certificate',
                'portfolio',
                'other'
            )
        ),

    CONSTRAINT ck_candidate_document_status
        CHECK (
            document_status IN (
                'uploaded',
                'scanning',
                'ready',
                'rejected',
                'archived'
            )
        ),

    CONSTRAINT ck_candidate_document_filename
        CHECK (
            LENGTH(BTRIM(original_filename)) BETWEEN 1 AND 255
            AND original_filename NOT IN ('.', '..')
            AND original_filename !~ '[/\\]'
        ),

    CONSTRAINT ck_candidate_document_storage_provider
        CHECK (
            storage_provider IN ('gcs', 's3', 'azure_blob', 'minio')
        ),

    CONSTRAINT ck_candidate_document_storage_key
        CHECK (
            LENGTH(BTRIM(storage_key)) BETWEEN 1 AND 1024
            AND storage_key !~ '^/'
            AND storage_key !~ '(^|/)\.\.?(/|$)'
        ),

    CONSTRAINT ck_candidate_document_mime_type
        CHECK (
            mime_type IN (
                'application/pdf',
                'application/msword',
                'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
                'text/plain',
                'image/jpeg',
                'image/png'
            )
        ),

    CONSTRAINT ck_candidate_document_file_size
        CHECK (file_size_bytes BETWEEN 1 AND 52428800),

    CONSTRAINT ck_candidate_document_checksum
        CHECK (
            checksum_sha256 IS NULL
            OR checksum_sha256 ~ '^[0-9a-fA-F]{64}$'
        ),

    CONSTRAINT ck_candidate_document_processed_at
        CHECK (
            processed_at IS NULL
            OR processed_at >= uploaded_at
        ),

    CONSTRAINT ck_candidate_document_archived_at
        CHECK (
            archived_at IS NULL
            OR archived_at >= uploaded_at
        ),

    CONSTRAINT ck_candidate_document_archived_status
        CHECK (
            (document_status = 'archived' AND archived_at IS NOT NULL)
            OR
            (document_status <> 'archived' AND archived_at IS NULL)
        ),

    CONSTRAINT ck_candidate_document_primary_type
        CHECK (NOT is_primary OR document_type = 'resume')
);

-- Efficient retrieval of a candidate's documents, newest first.
CREATE INDEX idx_candidate_document_profile_uploaded
    ON profile.candidate_document
       (candidate_profile_id, uploaded_at DESC);

-- Filter documents by candidate and processing state.
CREATE INDEX idx_candidate_document_profile_status
    ON profile.candidate_document
       (candidate_profile_id, document_status);

-- Only one primary resume per candidate.
CREATE UNIQUE INDEX uq_candidate_document_primary_resume
    ON profile.candidate_document (candidate_profile_id)
    WHERE is_primary = TRUE
      AND document_status <> 'archived';

COMMENT ON TABLE profile.candidate_document IS
    'Candidate document metadata; binary content is stored in object storage';

COMMENT ON COLUMN profile.candidate_document.storage_key IS
    'Private object-storage key, not a public URL or a signed download URL';

COMMENT ON COLUMN profile.candidate_document.checksum_sha256 IS
    'Optional SHA-256 checksum for integrity verification';

COMMENT ON COLUMN profile.candidate_document.document_status IS
    'Lifecycle state; ready should only be set after file validation and security scanning';

COMMIT;
