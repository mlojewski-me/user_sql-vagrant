USE nextcloud;

CREATE TABLE sql_user
(
  uid            INT         PRIMARY KEY AUTO_INCREMENT,
  username       VARCHAR(16) NOT NULL UNIQUE,
  display_name   TEXT        NULL,
  email          TEXT        NULL,
  quota          TEXT        NULL,
  home           TEXT        NULL,
  password       TEXT        NOT NULL,
  active         TINYINT(1)  NOT NULL DEFAULT '1',
  disabled       TINYINT(1)  NOT NULL DEFAULT '0',
  provide_avatar BOOLEAN     NOT NULL DEFAULT FALSE,
  salt           TEXT        NULL
);

CREATE TABLE sql_group
(
  gid   INT         PRIMARY KEY AUTO_INCREMENT,
  name  VARCHAR(16) NOT NULL UNIQUE,
  admin BOOLEAN     NOT NULL DEFAULT FALSE
);

CREATE TABLE sql_user_group
(
  uid INT NOT NULL,
  gid INT NOT NULL,
  PRIMARY KEY (uid, gid),
  FOREIGN KEY (uid) REFERENCES sql_user (uid),
  FOREIGN KEY (gid) REFERENCES sql_group (gid),
  INDEX user_group_username_idx (uid),
  INDEX user_group_group_name_idx (gid)
);

DROP PROCEDURE IF EXISTS load_sql_users;

DELIMITER #
CREATE PROCEDURE load_sql_users()
  BEGIN
    DECLARE v_users INT UNSIGNED DEFAULT 30;
    DECLARE v_groups INT UNSIGNED DEFAULT 3;
    DECLARE v_counter INT UNSIGNED DEFAULT 1;

    START TRANSACTION;

    WHILE v_counter <= v_groups DO
      INSERT INTO sql_group (name) VALUES (
        CONCAT('Group ', v_counter)
      );
      SET v_counter = v_counter + 1;
    END WHILE;

    SET v_counter = 1;

    WHILE v_counter <= v_users DO
      INSERT INTO sql_user (username, display_name, password, email) VALUES (
        CONCAT('user', v_counter), CONCAT('User ', v_counter), CONCAT('user', v_counter),
        CONCAT('user', v_counter, '@nextcloud')
      );
      INSERT INTO sql_user_group (gid, uid) VALUES (
        CONCAT(v_counter % v_groups + 1), v_counter
      );
      INSERT INTO sql_user_group (gid, uid) VALUES (
        CONCAT((v_counter + 1) % v_groups + 1), v_counter
      );
      SET v_counter = v_counter + 1;
    END WHILE;

    COMMIT;
  END #
DELIMITER ;

CALL load_sql_users();
