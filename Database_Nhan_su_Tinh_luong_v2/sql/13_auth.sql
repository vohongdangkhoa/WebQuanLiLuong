CREATE OR REPLACE PACKAGE PKG_AUTH AUTHID DEFINER AS

  PROCEDURE find_for_login(
    p_username IN VARCHAR2,
    p_rows OUT SYS_REFCURSOR
  );

  PROCEDURE find_for_session(
    p_user_id IN NUMBER,
    p_rows OUT SYS_REFCURSOR
  );

  PROCEDURE rehash_password(
    p_user_id IN NUMBER,
    p_old_hash IN VARCHAR2,
    p_expected_security_version IN NUMBER,
    p_new_hash IN VARCHAR2,
    p_updated OUT NUMBER
  );

END PKG_AUTH;
/
CREATE OR REPLACE PACKAGE BODY PKG_AUTH AS

  PROCEDURE find_for_login(
    p_username IN VARCHAR2,
    p_rows OUT SYS_REFCURSOR
  ) IS
  BEGIN
    OPEN p_rows FOR
      SELECT
        u.user_id,
        u.username,
        u.password_hash,
        u.is_active,
        u.security_version,
        r.role_code
      FROM APP_USER u
      LEFT JOIN USER_ROLE ur
        ON ur.user_id = u.user_id
      LEFT JOIN APP_ROLE r
        ON r.role_id = ur.role_id
      WHERE u.username = LOWER(TRIM(p_username))
      ORDER BY r.role_code;
  END find_for_login;
  PROCEDURE find_for_session(
  p_user_id IN NUMBER,
  p_rows OUT SYS_REFCURSOR
) IS
BEGIN
  OPEN p_rows FOR
    SELECT
      u.user_id,
      u.username,
      u.is_active,
      u.security_version,
      r.role_code
    FROM APP_USER u
    LEFT JOIN USER_ROLE ur
      ON ur.user_id = u.user_id
    LEFT JOIN APP_ROLE r
      ON r.role_id = ur.role_id
    WHERE u.user_id = p_user_id
    ORDER BY r.role_code;
END find_for_session;
PROCEDURE rehash_password(
  p_user_id IN NUMBER,
  p_old_hash IN VARCHAR2,
  p_expected_security_version IN NUMBER,
  p_new_hash IN VARCHAR2,
  p_updated OUT NUMBER
) IS
BEGIN
  IF p_new_hash IS NULL OR LENGTH(p_new_hash) > 500 THEN
    RAISE_APPLICATION_ERROR(-20200, 'Invalid password hash');
  END IF;

  UPDATE APP_USER
  SET password_hash = p_new_hash
  WHERE user_id = p_user_id
    AND password_hash = p_old_hash
    AND security_version = p_expected_security_version
    AND is_active = 'Y';

  p_updated := SQL%ROWCOUNT;
END rehash_password;

END PKG_AUTH;
/
GRANT EXECUTE ON PKG_AUTH TO PAYROLL_API;