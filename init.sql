USE nextcloud;

CREATE TABLE sql_user
(
  username       VARCHAR(16) PRIMARY KEY,
  display_name   TEXT        NULL,
  email          TEXT        NULL,
  quota          TEXT        NULL,
  home           TEXT        NULL,
  password       TEXT        NOT NULL,
  active         TINYINT(1)  NOT NULL DEFAULT '1',
  provide_avatar BOOLEAN     NOT NULL DEFAULT FALSE,
  salt           TEXT        NULL
);

CREATE TABLE sql_group
(
  name         VARCHAR(16) PRIMARY KEY,
  display_name TEXT        NULL,
  admin        BOOLEAN     NOT NULL DEFAULT FALSE
);

CREATE TABLE sql_user_group
(
  username   VARCHAR(16) NOT NULL,
  group_name VARCHAR(16) NOT NULL,
  PRIMARY KEY (username, group_name),
  FOREIGN KEY (username) REFERENCES sql_user (username),
  FOREIGN KEY (group_name) REFERENCES sql_group (name),
  INDEX user_group_username_idx (username),
  INDEX user_group_group_name_idx (group_name)
);

DROP PROCEDURE IF EXISTS load_sql_users;

DELIMITER #
CREATE PROCEDURE load_sql_users()
  BEGIN
    DECLARE v_users INT UNSIGNED DEFAULT 100;
    DECLARE v_groups INT UNSIGNED DEFAULT 5;
    DECLARE v_counter INT UNSIGNED DEFAULT 0;

    START TRANSACTION;

    WHILE v_counter < v_groups DO
      INSERT INTO sql_group (name, display_name) VALUES (
        CONCAT('group', v_counter), CONCAT('Group ', v_counter)
      );
      SET v_counter = v_counter + 1;
    END WHILE;

    SET v_counter = 0;

    WHILE v_counter < v_users DO
      INSERT INTO sql_user (username, display_name, password, email) VALUES (
        CONCAT('user', v_counter), CONCAT('User ', v_counter), CONCAT('user', v_counter),
        CONCAT('user', v_counter, '@nextcloud')
      );
      INSERT INTO sql_user_group (group_name, username) VALUES (
        CONCAT('group', v_counter % v_groups), CONCAT('user', v_counter)
      );
      INSERT INTO sql_user_group (group_name, username) VALUES (
        CONCAT('group', (v_counter + 1) % v_groups), CONCAT('user', v_counter)
      );
      SET v_counter = v_counter + 1;
    END WHILE;

    COMMIT;
  END #
DELIMITER ;

CALL load_sql_users();
