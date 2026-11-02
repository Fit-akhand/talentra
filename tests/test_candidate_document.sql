
-- Covers: BR-008, REQ-012, SEC-009   (generated from the registers by scripts/lifecycle/tag_tests.py)
BEGIN;

DO $$
DECLARE
    v_user_id BIGINT;
    v_candidate_id BIGINT;
    v_document_id BIGINT;
BEGIN
    INSERT INTO core.user_account (email)
    VALUES ('migration006-test@example.invalid')
    RETURNING id INTO v_user_id;

    INSERT INTO profile.candidate_profile (user_account_id)
    VALUES (v_user_id)
    RETURNING id INTO v_candidate_id;

    INSERT INTO profile.candidate_document (
        candidate_profile_id,
        document_type,
        document_status,
        original_filename,
        storage_provider,
        storage_key,
        mime_type,
        file_size_bytes,
        checksum_sha256,
        is_primary
    )
    VALUES (
        v_candidate_id,
        'resume',
        'ready',
        'resume.pdf',
        'minio',
        'candidate-documents/test/resume.pdf',
        'application/pdf',
        1024,
        REPEAT('a', 64),
        TRUE
    )
    RETURNING id INTO v_document_id;

    RAISE NOTICE 'PASS: valid candidate document inserted';

    -- A second primary resume must fail.
    BEGIN
        INSERT INTO profile.candidate_document (
            candidate_profile_id,
            document_type,
            document_status,
            original_filename,
            storage_provider,
            storage_key,
            mime_type,
            file_size_bytes,
            is_primary
        )
        VALUES (
            v_candidate_id,
            'resume',
            'uploaded',
            'resume2.pdf',
            'minio',
            'candidate-documents/test/resume2.pdf',
            'application/pdf',
            2048,
            TRUE
        );

        RAISE EXCEPTION 'FAIL: duplicate primary resume accepted';
    EXCEPTION
        WHEN unique_violation THEN
            RAISE NOTICE 'PASS: duplicate primary resume rejected';
    END;

    -- A duplicate storage reference must fail.
    BEGIN
        INSERT INTO profile.candidate_document (
            candidate_profile_id,
            original_filename,
            storage_provider,
            storage_key,
            mime_type,
            file_size_bytes
        )
        VALUES (
            v_candidate_id,
            'duplicate.pdf',
            'minio',
            'candidate-documents/test/resume.pdf',
            'application/pdf',
            1024
        );

        RAISE EXCEPTION 'FAIL: duplicate storage reference accepted';
    EXCEPTION
        WHEN unique_violation THEN
            RAISE NOTICE 'PASS: duplicate storage reference rejected';
    END;

    -- Unsupported MIME types must fail.
    BEGIN
        INSERT INTO profile.candidate_document (
            candidate_profile_id,
            original_filename,
            storage_provider,
            storage_key,
            mime_type,
            file_size_bytes
        )
        VALUES (
            v_candidate_id,
            'script.exe',
            'minio',
            'candidate-documents/test/script.exe',
            'application/x-msdownload',
            1024
        );

        RAISE EXCEPTION 'FAIL: unsupported MIME type accepted';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE 'PASS: unsupported MIME type rejected';
    END;

    -- Files exceeding 50 MiB must fail.
    BEGIN
        INSERT INTO profile.candidate_document (
            candidate_profile_id,
            original_filename,
            storage_provider,
            storage_key,
            mime_type,
            file_size_bytes
        )
        VALUES (
            v_candidate_id,
            'large.pdf',
            'minio',
            'candidate-documents/test/large.pdf',
            'application/pdf',
            52428801
        );

        RAISE EXCEPTION 'FAIL: oversized document accepted';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE 'PASS: oversized document rejected';
    END;

    -- Archived status requires archived_at.
    BEGIN
        INSERT INTO profile.candidate_document (
            candidate_profile_id,
            document_status,
            original_filename,
            storage_provider,
            storage_key,
            mime_type,
            file_size_bytes
        )
        VALUES (
            v_candidate_id,
            'archived',
            'archived.pdf',
            'minio',
            'candidate-documents/test/archived.pdf',
            'application/pdf',
            1024
        );

        RAISE EXCEPTION 'FAIL: archive without timestamp accepted';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE 'PASS: archive timestamp requirement enforced';
    END;

    -- Non-resume documents cannot be primary.
    BEGIN
        INSERT INTO profile.candidate_document (
            candidate_profile_id,
            document_type,
            original_filename,
            storage_provider,
            storage_key,
            mime_type,
            file_size_bytes,
            is_primary
        )
        VALUES (
            v_candidate_id,
            'certificate',
            'certificate.pdf',
            'minio',
            'candidate-documents/test/certificate.pdf',
            'application/pdf',
            1024,
            TRUE
        );

        RAISE EXCEPTION 'FAIL: non-resume primary document accepted';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE 'PASS: primary document type constraint enforced';
    END;

    RAISE NOTICE 'PASS: candidate document constraint suite completed';
END
$$;

ROLLBACK;
