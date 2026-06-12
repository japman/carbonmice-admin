SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: admin; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA admin;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: admin_users; Type: TABLE; Schema: admin; Owner: -
--

CREATE TABLE admin.admin_users (
    id bigint NOT NULL,
    email_address character varying NOT NULL,
    password_digest character varying NOT NULL,
    name character varying NOT NULL,
    role integer DEFAULT 0 NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: admin_users_id_seq; Type: SEQUENCE; Schema: admin; Owner: -
--

CREATE SEQUENCE admin.admin_users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: admin_users_id_seq; Type: SEQUENCE OWNED BY; Schema: admin; Owner: -
--

ALTER SEQUENCE admin.admin_users_id_seq OWNED BY admin.admin_users.id;


--
-- Name: ar_internal_metadata; Type: TABLE; Schema: admin; Owner: -
--

CREATE TABLE admin.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: schema_migrations; Type: TABLE; Schema: admin; Owner: -
--

CREATE TABLE admin.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: sessions; Type: TABLE; Schema: admin; Owner: -
--

CREATE TABLE admin.sessions (
    id bigint NOT NULL,
    admin_user_id bigint NOT NULL,
    ip_address character varying,
    user_agent character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: sessions_id_seq; Type: SEQUENCE; Schema: admin; Owner: -
--

CREATE SEQUENCE admin.sessions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sessions_id_seq; Type: SEQUENCE OWNED BY; Schema: admin; Owner: -
--

ALTER SEQUENCE admin.sessions_id_seq OWNED BY admin.sessions.id;


--
-- Name: admin_users id; Type: DEFAULT; Schema: admin; Owner: -
--

ALTER TABLE ONLY admin.admin_users ALTER COLUMN id SET DEFAULT nextval('admin.admin_users_id_seq'::regclass);


--
-- Name: sessions id; Type: DEFAULT; Schema: admin; Owner: -
--

ALTER TABLE ONLY admin.sessions ALTER COLUMN id SET DEFAULT nextval('admin.sessions_id_seq'::regclass);


--
-- Name: admin_users admin_users_pkey; Type: CONSTRAINT; Schema: admin; Owner: -
--

ALTER TABLE ONLY admin.admin_users
    ADD CONSTRAINT admin_users_pkey PRIMARY KEY (id);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: admin; Owner: -
--

ALTER TABLE ONLY admin.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: admin; Owner: -
--

ALTER TABLE ONLY admin.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: sessions sessions_pkey; Type: CONSTRAINT; Schema: admin; Owner: -
--

ALTER TABLE ONLY admin.sessions
    ADD CONSTRAINT sessions_pkey PRIMARY KEY (id);


--
-- Name: index_admin_users_on_email_address; Type: INDEX; Schema: admin; Owner: -
--

CREATE UNIQUE INDEX index_admin_users_on_email_address ON admin.admin_users USING btree (email_address);


--
-- Name: index_sessions_on_admin_user_id; Type: INDEX; Schema: admin; Owner: -
--

CREATE INDEX index_sessions_on_admin_user_id ON admin.sessions USING btree (admin_user_id);


--
-- Name: sessions fk_rails_e322124d9d; Type: FK CONSTRAINT; Schema: admin; Owner: -
--

ALTER TABLE ONLY admin.sessions
    ADD CONSTRAINT fk_rails_e322124d9d FOREIGN KEY (admin_user_id) REFERENCES admin.admin_users(id);


--
-- PostgreSQL database dump complete
--

SET search_path TO admin, public;

INSERT INTO "schema_migrations" (version) VALUES
('20260612092717');

