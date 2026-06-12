-- TEST FIXTURE: structure-only snapshot of the Go backend's public schema.
-- Regenerate with the command in README when the Go schema changes. Never edit by hand.
--
-- PostgreSQL database dump
--


-- Dumped from database version 17.10 (Debian 17.10-1.pgdg13+1)
-- Dumped by pg_dump version 18.4

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
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

-- CREATE SCHEMA public;  -- already exists in test DB; do not re-create


--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS 'standard public schema';


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: airports; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.airports (
    id bigint NOT NULL,
    iata_code character varying(3) NOT NULL,
    icao_code character varying(4),
    name_th text NOT NULL,
    name_en text NOT NULL,
    province_th text,
    province_en text,
    country_code text,
    latitude numeric(10,7) NOT NULL,
    longitude numeric(10,7) NOT NULL,
    is_domestic boolean,
    is_active boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now(),
    deleted_at timestamp without time zone,
    created_by character varying(255) NOT NULL,
    updated_by character varying(255) NOT NULL,
    deleted_by character varying(255)
);


--
-- Name: airports_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.airports_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: airports_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.airports_id_seq OWNED BY public.airports.id;


--
-- Name: booth_pricing_tiers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.booth_pricing_tiers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_by character varying(255) NOT NULL,
    updated_by character varying(255),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone,
    deleted_at timestamp without time zone,
    min integer NOT NULL,
    max integer NOT NULL,
    price_per_unit numeric(10,2) DEFAULT 0.00 NOT NULL,
    event_type_id uuid NOT NULL,
    CONSTRAINT booth_pricing_tiers_check CHECK (((max > 0) AND (max >= min))),
    CONSTRAINT booth_pricing_tiers_min_check CHECK ((min >= 0))
);


--
-- Name: carbon_categories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.carbon_categories (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_by character varying(255) NOT NULL,
    updated_by character varying(255),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone,
    deleted_at timestamp without time zone,
    name_thai character varying(255) NOT NULL,
    name_eng character varying(255) NOT NULL,
    carbon_scope_id uuid NOT NULL
);


--
-- Name: carbon_credits; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.carbon_credits (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_by character varying(255) NOT NULL,
    updated_by character varying(255),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone,
    deleted_at timestamp without time zone,
    user_id uuid NOT NULL,
    carbon_credit bigint NOT NULL,
    carbon_offset_source_id uuid
);


--
-- Name: carbon_emission_factors; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.carbon_emission_factors (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_by character varying(255) NOT NULL,
    updated_by character varying(255),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone,
    deleted_at timestamp without time zone,
    name character varying(255) NOT NULL,
    description text,
    source text NOT NULL,
    value_per_unit numeric(12,6) NOT NULL,
    unit_title character varying(255) NOT NULL,
    carbon_category_id uuid NOT NULL,
    unit_id uuid,
    identifier character varying(255)
);


--
-- Name: carbon_emissions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.carbon_emissions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_by character varying(255) NOT NULL,
    updated_by character varying(255),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone,
    deleted_at timestamp without time zone,
    pre_event_emission numeric(19,3) DEFAULT 0.0000 NOT NULL,
    post_event_emission numeric(10,4),
    event_id uuid NOT NULL,
    carbon_category_id uuid NOT NULL,
    unit_id uuid NOT NULL
);


--
-- Name: carbon_offset_pricing_tiers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.carbon_offset_pricing_tiers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_by character varying(255) NOT NULL,
    updated_by character varying(255),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone,
    deleted_at timestamp without time zone,
    min_emission integer NOT NULL,
    max_emission integer,
    unit_id uuid NOT NULL,
    price_per_emission numeric(10,2) DEFAULT 0.00 NOT NULL,
    carbon_offset_source_id uuid NOT NULL,
    CONSTRAINT carbon_offset_pricing_tiers_min_emission_check CHECK ((min_emission >= 0))
);


--
-- Name: carbon_offset_sources; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.carbon_offset_sources (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_by character varying(255) NOT NULL,
    updated_by character varying(255),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone,
    deleted_at timestamp without time zone,
    name character varying(255) NOT NULL,
    name_th character varying(255)
);


--
-- Name: carbon_scopes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.carbon_scopes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_by character varying(255) NOT NULL,
    updated_by character varying(255),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone,
    deleted_at timestamp without time zone,
    name character varying(255) NOT NULL,
    CONSTRAINT carbon_scopes_name_check CHECK (((name)::text = ANY ((ARRAY['scope_1'::character varying, 'scope_2'::character varying, 'scope_3'::character varying])::text[])))
);


--
-- Name: customers_quotations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.customers_quotations (
    legacy_id integer,
    customer_type text,
    org_prefix text,
    org_name text,
    industry_group text,
    industry_size text,
    tax_id text,
    email text,
    phone text,
    branch_type text,
    branch_code text,
    address_line text,
    postal_code text,
    province text,
    district text,
    subdistrict text,
    remark text,
    quotation_no text,
    created_by text,
    updated_by text,
    deleted_by text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    deleted_at timestamp without time zone,
    event_id uuid NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    address_line_2 text,
    address_line_3 text
);


--
-- Name: dashboard_images; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dashboard_images (
    id uuid NOT NULL,
    event_id uuid NOT NULL,
    type character varying(255) NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone,
    deleted_at timestamp without time zone,
    created_by character varying(255)
);


--
-- Name: dashboards; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dashboards (
    id uuid NOT NULL,
    event_name_th character varying(255) NOT NULL,
    event_name_en character varying(255) NOT NULL,
    display_date character varying(255) NOT NULL,
    org_name_th character varying(255) NOT NULL,
    org_name_en character varying(255) NOT NULL,
    location character varying(255) NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone,
    deleted_at timestamp without time zone,
    created_by character varying(255),
    location_en text,
    dashboard_lang character varying(2) DEFAULT 'th'::character varying NOT NULL,
    show_participant_count boolean DEFAULT true NOT NULL
);


--
-- Name: electricities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.electricities (
    id bigint NOT NULL,
    event_schedule_id uuid NOT NULL,
    has_separate_meter boolean NOT NULL,
    start_meter integer,
    end_meter integer,
    start_meter_url character varying(255),
    end_meter_url character varying(255),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone
);


--
-- Name: electricity_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.electricity_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: electricity_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.electricity_id_seq OWNED BY public.electricities.id;


--
-- Name: email_verifications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.email_verifications (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_by character varying(255) NOT NULL,
    updated_by character varying(255),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone,
    deleted_at timestamp without time zone,
    event_id uuid NOT NULL,
    user_raw_id character varying(255) NOT NULL,
    user_email character varying(255) NOT NULL
);


--
-- Name: event_accommodations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.event_accommodations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    event_id uuid NOT NULL,
    created_by character varying(255) NOT NULL,
    updated_by character varying(255),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone,
    deleted_at timestamp without time zone,
    accommodated_participants integer,
    distance_from_accommodation integer,
    hotel_types character varying(255),
    is_transport_provided boolean,
    bus integer,
    van integer,
    car integer
);


--
-- Name: event_agencies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.event_agencies (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_by character varying(255) NOT NULL,
    updated_by character varying(255),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone,
    deleted_at timestamp without time zone,
    event_id uuid NOT NULL,
    name_thai character varying(255),
    name_eng character varying(255),
    address text,
    logo_url character varying(255)
);


--
-- Name: event_api_key; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.event_api_key (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    event_id uuid NOT NULL,
    name character varying(100) NOT NULL,
    key_hash character varying(255) NOT NULL,
    key_prefix character varying(50) NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    expired_at timestamp without time zone,
    last_used_at timestamp without time zone,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    created_by character varying(255)
);


--
-- Name: event_certificate_issuers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.event_certificate_issuers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    event_id uuid NOT NULL,
    name_th character varying(255),
    name_en character varying(255),
    created_by character varying(255) NOT NULL,
    updated_by character varying(255),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone,
    deleted_at timestamp without time zone
);


--
-- Name: event_create_render_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.event_create_render_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_by character varying(255) NOT NULL,
    updated_by character varying(255),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone,
    deleted_at timestamp without time zone,
    item_subtype_id uuid,
    item_unit_id uuid NOT NULL,
    is_giveaway boolean NOT NULL
);


--
-- Name: event_customer_contacts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.event_customer_contacts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_by character varying(255) NOT NULL,
    updated_by character varying(255),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone,
    deleted_at timestamp without time zone,
    event_id uuid NOT NULL,
    name character varying(255) NOT NULL,
    phone_number character varying(255) NOT NULL,
    email character varying(255) NOT NULL,
    remark text
);


--
-- Name: event_documents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.event_documents (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    event_id uuid NOT NULL,
    category character varying(255) NOT NULL,
    title text NOT NULL,
    file_name text NOT NULL,
    file_key text NOT NULL,
    mime_type character varying(255) NOT NULL,
    file_size bigint NOT NULL,
    created_by character varying(255) NOT NULL,
    updated_by character varying(255) NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    slot character varying(255),
    CONSTRAINT event_documents_category_check CHECK (((category)::text = ANY ((ARRAY['carbon_data'::character varying, 'carbon_neutral_event'::character varying, 'financial'::character varying])::text[])))
);


--
-- Name: event_exhibition_booths; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.event_exhibition_booths (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_by character varying(255) NOT NULL,
    updated_by character varying(255),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone,
    deleted_at timestamp without time zone,
    value numeric(10,2) NOT NULL,
    name character varying(255) NOT NULL,
    multiplier integer NOT NULL,
    unit_id uuid NOT NULL,
    event_id uuid NOT NULL,
    exhibition_booth_option_id uuid,
    weight numeric(10,4) DEFAULT 0,
    transport_type character varying(255),
    CONSTRAINT event_exhibition_booths_multiplier_check CHECK ((multiplier > 0))
);


--
-- Name: event_giveaways; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.event_giveaways (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    material_type character varying(255),
    quantity integer,
    weight numeric(10,2),
    type character varying(255),
    event_id uuid NOT NULL,
    created_by character varying(255) NOT NULL,
    updated_by character varying(255),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone,
    deleted_at timestamp without time zone
);


--
-- Name: event_images; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.event_images (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_by character varying(255) NOT NULL,
    updated_by character varying(255),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone,
    deleted_at timestamp without time zone,
    event_id uuid NOT NULL,
    image_url character varying(255),
    image_type character varying(255)
);


--
-- Name: event_item_and_giveaway_item_subtypes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.event_item_and_giveaway_item_subtypes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_by character varying(255) NOT NULL,
    updated_by character varying(255),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone,
    deleted_at timestamp without time zone,
    item_type_id uuid NOT NULL,
    identifier character varying(255) NOT NULL,
    weight_per_piece numeric(10,6) NOT NULL,
    material_type_id uuid NOT NULL,
    name character varying(255) NOT NULL
);


--
-- Name: event_item_and_giveaway_item_types; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.event_item_and_giveaway_item_types (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_by character varying(255) NOT NULL,
    updated_by character varying(255),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone,
    deleted_at timestamp without time zone,
    identifier character varying(255) NOT NULL,
    name character varying(255) NOT NULL
);


--
-- Name: event_item_and_giveaway_item_units; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.event_item_and_giveaway_item_units (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_by character varying(255) NOT NULL,
    updated_by character varying(255),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone,
    deleted_at timestamp without time zone,
    name character varying(255) NOT NULL,
    identifier character varying(255) NOT NULL,
    multiplier numeric(10,6) NOT NULL
);


--
-- Name: event_item_and_giveaway_material_types; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.event_item_and_giveaway_material_types (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_by character varying(255) NOT NULL,
    updated_by character varying(255),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone,
    deleted_at timestamp without time zone,
    emission_factor_id uuid NOT NULL,
    identifier character varying(255) NOT NULL,
    name character varying(255) NOT NULL
);


--
-- Name: event_item_and_giveaways; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.event_item_and_giveaways (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_by character varying(255) NOT NULL,
    updated_by character varying(255),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone,
    deleted_at timestamp without time zone,
    event_id uuid NOT NULL,
    item_type_id uuid,
    item_subtype_id uuid,
    item_unit_id uuid NOT NULL,
    quantity bigint NOT NULL,
    weight numeric(28,10),
    emission_factor numeric(10,6),
    is_giveaway boolean NOT NULL,
    weight_changed boolean DEFAULT false NOT NULL,
    material_name character varying(255),
    emission_reference character varying(255),
    item_material_id uuid
);


--
-- Name: event_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.event_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    material_type character varying(255),
    quantity integer,
    weight numeric(10,2),
    type character varying(255),
    event_id uuid NOT NULL,
    created_by character varying(255) NOT NULL,
    updated_by character varying(255),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone,
    deleted_at timestamp without time zone
);


--
-- Name: event_items_sub_types; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.event_items_sub_types (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    event_item_id uuid NOT NULL,
    material_type character varying(255) NOT NULL,
    sub_type character varying(255) NOT NULL,
    weight numeric(10,2),
    quantity integer,
    created_by character varying(255),
    updated_by character varying(255),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone,
    deleted_at timestamp without time zone
);


--
-- Name: event_locations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.event_locations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_by character varying(255) NOT NULL,
    updated_by character varying(255),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone,
    deleted_at timestamp without time zone,
    event_id uuid NOT NULL,
    name character varying(255),
    room_name character varying(255),
    region character varying(255),
    province character varying(255),
    district character varying(255),
    sub_district character varying(255),
    postcode character varying(5),
    address_thai text,
    address_eng text
);


--
-- Name: event_orders; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.event_orders (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_by character varying(255) NOT NULL,
    updated_by character varying(255),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone,
    deleted_at timestamp without time zone,
    event_id uuid NOT NULL,
    package_price numeric(10,4) NOT NULL,
    order_number character varying(255),
    order_date timestamp without time zone,
    quotation_number character varying(255),
    quotation_date timestamp without time zone,
    licence_fee numeric(10,4) DEFAULT 0 NOT NULL
);


--
-- Name: event_pricing_tiers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.event_pricing_tiers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    min_participants integer NOT NULL,
    max_participants integer,
    price_per_person numeric(10,2) DEFAULT 0.00 NOT NULL,
    created_by character varying(255) NOT NULL,
    updated_by character varying(255),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone,
    deleted_at timestamp without time zone,
    CONSTRAINT event_pricing_tiers_min_participants_check CHECK ((min_participants >= 0))
);


--
-- Name: event_schedules; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.event_schedules (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_by character varying(255) NOT NULL,
    updated_by character varying(255),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone,
    deleted_at timestamp without time zone,
    start_date_time timestamp with time zone NOT NULL,
    end_date_time timestamp with time zone NOT NULL,
    event_id uuid NOT NULL,
    CONSTRAINT event_schedules_check CHECK ((start_date_time <= end_date_time)),
    CONSTRAINT event_schedules_check1 CHECK ((end_date_time > start_date_time))
);


--
-- Name: event_statuses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.event_statuses (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_by character varying(255) NOT NULL,
    updated_by character varying(255),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone,
    deleted_at timestamp without time zone,
    running_order numeric(10,2) NOT NULL,
    name_eng character varying(255) DEFAULT 'draft'::character varying NOT NULL,
    name_thai character varying(255) DEFAULT 'บันทึกร่าง'::character varying NOT NULL
);


--
-- Name: event_tax_invoices; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.event_tax_invoices (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_by character varying(255) NOT NULL,
    updated_by character varying(255),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone,
    deleted_at timestamp without time zone,
    event_id uuid NOT NULL,
    taxpayer_type character varying(255) NOT NULL,
    taxpayer_name character varying(255) NOT NULL,
    taxpayer_identification_number character varying(255) NOT NULL,
    branch character varying(255),
    branch_number character varying(255),
    house_number character varying(255) NOT NULL,
    district character varying(255) NOT NULL,
    sub_district character varying(255) NOT NULL,
    province character varying(255) NOT NULL,
    postcode character varying(255) NOT NULL,
    email character varying(255) NOT NULL,
    remark text,
    phone_number character varying(255) NOT NULL,
    accept_agreement boolean DEFAULT false,
    accept_privacy_notice boolean DEFAULT false,
    accept_collected_data boolean DEFAULT false
);


--
-- Name: event_templates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.event_templates (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(255) NOT NULL,
    description text,
    image_url text,
    license_fee numeric(10,2) NOT NULL,
    is_active boolean DEFAULT true,
    created_by character varying(255) NOT NULL,
    updated_by character varying(255),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone,
    deleted_at timestamp without time zone,
    event_type_id uuid NOT NULL
);


--
-- Name: event_types; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.event_types (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(255) NOT NULL,
    created_by character varying(255) NOT NULL,
    updated_by character varying(255),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone,
    deleted_at timestamp without time zone
);


--
-- Name: events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.events (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name_thai character varying(255),
    name_eng character varying(255),
    max_participants_per_day integer,
    foreign_participants_ratio numeric(10,2),
    online_participants_per_day integer,
    has_accommodation boolean,
    area numeric(10,2),
    outdoor_area_ratio numeric(10,2),
    renewable_energy_ratio numeric(10,2),
    has_exhibition_booth_transportation boolean,
    has_exhibition_booth boolean,
    exhibition_booth_transportation_method character varying(255),
    exhibition_booth_type character varying(255),
    has_giveaways boolean,
    is_carbon_neutral_event boolean,
    created_by character varying(255) NOT NULL,
    updated_by character varying(255),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone,
    deleted_at timestamp without time zone,
    event_template_id uuid NOT NULL,
    accommodated_participants integer DEFAULT 0,
    schedules_type character varying(255),
    event_status character varying(255),
    organizers_participants integer,
    foreign_organizers_participants integer,
    online_organizers_participants integer,
    conference_staff_participants integer,
    organizer_participants integer,
    online_organizer_participants integer,
    max_foreign_participants_per_day integer,
    foreign_organizer_participants integer,
    area_name character varying(255),
    province character varying(255),
    has_event_items boolean,
    total_nights integer,
    logo_url character varying(255),
    outdoor_area_ratio_known boolean,
    renewable_energy_ratio_known boolean,
    decoration_weight integer,
    has_new_exhibition_booth boolean,
    register_image_url character varying(255),
    payment_status character varying(255),
    quota_deducted boolean DEFAULT false,
    carbon_offset_source_id uuid,
    CONSTRAINT events_payment_status_check CHECK (((payment_status)::text = ANY ((ARRAY['pending_payment'::character varying, 'paid'::character varying])::text[])))
);


--
-- Name: exhibition_booth_options; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.exhibition_booth_options (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_by character varying(255) NOT NULL,
    updated_by character varying(255),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone,
    deleted_at timestamp without time zone,
    name character varying(255) NOT NULL,
    multiplier integer NOT NULL,
    unit_id uuid NOT NULL,
    CONSTRAINT exhibition_booth_options_multiplier_check CHECK ((multiplier > 0))
);


--
-- Name: flight_routes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.flight_routes (
    id bigint NOT NULL,
    origin_airport_id bigint NOT NULL,
    destination_airport_id bigint NOT NULL,
    haversine_distance numeric(10,2) NOT NULL,
    uplift_factor numeric(5,4) DEFAULT 1.0000 NOT NULL,
    km_distance numeric(10,2) NOT NULL,
    route_type character varying(20) DEFAULT 'domestic'::character varying NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone,
    deleted_at timestamp without time zone,
    created_by character varying(255) NOT NULL,
    updated_by character varying(255),
    CONSTRAINT chk_origin_destination_not_same CHECK ((origin_airport_id <> destination_airport_id))
);


--
-- Name: flight_routes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.flight_routes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: flight_routes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.flight_routes_id_seq OWNED BY public.flight_routes.id;


--
-- Name: food_and_beverages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.food_and_beverages (
    id bigint NOT NULL,
    event_schedule_id uuid NOT NULL,
    general_and_halal_set integer,
    vegetarian_set integer,
    snack_set integer,
    vegetarian_snack_set integer,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone
);


--
-- Name: food_and_beverage_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.food_and_beverage_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: food_and_beverage_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.food_and_beverage_id_seq OWNED BY public.food_and_beverages.id;


--
-- Name: form_template; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.form_template (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(255) NOT NULL,
    description text,
    is_active boolean DEFAULT true,
    created_by character varying(255) NOT NULL,
    updated_by character varying(255),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone,
    deleted_at timestamp without time zone
);


--
-- Name: forms; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.forms (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name_thai character varying(255) NOT NULL,
    name_eng character varying(255),
    form_template_id uuid NOT NULL,
    content jsonb NOT NULL
);


--
-- Name: goose_db_version; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.goose_db_version (
    id integer NOT NULL,
    version_id bigint NOT NULL,
    is_applied boolean NOT NULL,
    tstamp timestamp without time zone DEFAULT now() NOT NULL
);


--
-- Name: goose_db_version_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.goose_db_version ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.goose_db_version_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: international_to_thailand_distances; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.international_to_thailand_distances (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    depature_country character varying(255) NOT NULL,
    distance integer,
    created_by character varying(255) NOT NULL,
    updated_by character varying(255),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone,
    deleted_at timestamp without time zone
);


--
-- Name: precal_snapshots; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.precal_snapshots (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_by character varying(255) NOT NULL,
    updated_by character varying(255),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone,
    deleted_at timestamp without time zone,
    event_id uuid NOT NULL,
    content jsonb NOT NULL,
    ef jsonb
);


--
-- Name: province_road_distances; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.province_road_distances (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    depature character varying(255) NOT NULL,
    destination character varying(255) NOT NULL,
    depature_en character varying(255) NOT NULL,
    destination_en character varying(255) NOT NULL,
    distance integer,
    created_by character varying(255) NOT NULL,
    updated_by character varying(255),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone,
    deleted_at timestamp without time zone
);


--
-- Name: short_links; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.short_links (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    code character varying(32) NOT NULL,
    event_id uuid NOT NULL,
    survey_id uuid NOT NULL,
    page_type character varying(32) DEFAULT 'forms'::character varying NOT NULL,
    created_by character varying(255) NOT NULL,
    updated_by character varying(255),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone,
    deleted_at timestamp without time zone
);


--
-- Name: survey_answers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.survey_answers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_type character varying(20) NOT NULL,
    pdpa_consent boolean DEFAULT false NOT NULL,
    is_personal_vehicle boolean DEFAULT false NOT NULL,
    organization_vehicle_type character varying(100) NOT NULL,
    personal_vehicle_type character varying(100) NOT NULL,
    distant character varying(50),
    departure_province character varying(100),
    bangkok_district character varying(100),
    departure_station character varying(100),
    domestic_departure_airport_province character varying(100),
    departure_country character varying(100),
    destination_airport character varying(100),
    travel_class character varying(50),
    is_receive_certification boolean,
    first_name character varying(100),
    last_name character varying(100),
    email character varying(255),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    created_by character varying(255) NOT NULL,
    updated_by character varying(255),
    survey_id uuid NOT NULL,
    deleted_at timestamp without time zone,
    transport_emission numeric(10,4),
    distance_km integer
);


--
-- Name: survey_participation_dates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.survey_participation_dates (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    survey_answer_id uuid NOT NULL,
    participation_date timestamp without time zone NOT NULL,
    attended boolean NOT NULL,
    created_by character varying(255) NOT NULL,
    updated_by character varying(255),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    deleted_at timestamp without time zone
);


--
-- Name: survey_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.survey_settings (
    survey_id uuid NOT NULL,
    user_type character varying(20) NOT NULL,
    name_redirect character varying(100),
    url_redirect text,
    is_redirect boolean DEFAULT false NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    is_custom boolean DEFAULT false NOT NULL,
    CONSTRAINT chk_url_when_redirect CHECK (((is_redirect = false) OR ((is_redirect = true) AND (name_redirect IS NOT NULL) AND (url_redirect IS NOT NULL) AND (url_redirect <> ''::text))))
);


--
-- Name: survey_utilities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.survey_utilities (
    id bigint NOT NULL,
    event_id uuid NOT NULL,
    has_separate boolean NOT NULL,
    is_closed boolean,
    type character varying(50),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone
);


--
-- Name: survey_utilities_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.survey_utilities_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: survey_utilities_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.survey_utilities_id_seq OWNED BY public.survey_utilities.id;


--
-- Name: surveys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.surveys (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    event_id uuid,
    type character varying(10) NOT NULL,
    is_closed boolean NOT NULL,
    created_by character varying(255) NOT NULL,
    updated_by character varying(255),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone,
    deleted_at timestamp without time zone,
    actual_participant integer,
    is_published boolean DEFAULT false NOT NULL
);


--
-- Name: tgo_registration_submissions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tgo_registration_submissions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    event_id uuid NOT NULL,
    register_image_url text,
    event_category character varying(255),
    event_name_thai text,
    event_name_eng text,
    venue_name text,
    cert_issuer_name_thai text,
    cert_issuer_name_eng text,
    event_start_date date,
    event_end_date date,
    offset_amount_kg numeric(18,6),
    org_prefix character varying(50),
    org_name text,
    industry_group character varying(255),
    industry_size character varying(255),
    tax_id character varying(20),
    email character varying(255),
    phone character varying(50),
    address_line text,
    address_line_2 text DEFAULT ''::text NOT NULL,
    address_line_3 text DEFAULT ''::text NOT NULL,
    subdistrict character varying(255),
    district character varying(255),
    province character varying(255),
    postal_code character varying(10),
    bundle_url text,
    status character varying(32) DEFAULT 'sent'::character varying NOT NULL,
    error_msg text,
    sent_by character varying(255),
    sent_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: units; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.units (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_by character varying(255) NOT NULL,
    updated_by character varying(255),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone,
    deleted_at timestamp without time zone,
    code character varying(255) NOT NULL,
    multiplier numeric(10,4) NOT NULL,
    CONSTRAINT units_multiplier_check CHECK ((multiplier > (0)::numeric))
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    display_name character varying(255),
    raw_id character varying(255) NOT NULL,
    email character varying(255),
    role character varying(255) NOT NULL,
    created_by character varying(255) NOT NULL,
    updated_by character varying(255),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone,
    deleted_at timestamp without time zone,
    event_quota integer DEFAULT 0,
    is_package_user boolean DEFAULT false
);


--
-- Name: waste_bombers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.waste_bombers (
    id bigint NOT NULL,
    event_schedule_id uuid NOT NULL,
    has_separate_waste boolean NOT NULL,
    type character varying(50),
    weight real,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone
);


--
-- Name: waste_bomber_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.waste_bomber_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: waste_bomber_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.waste_bomber_id_seq OWNED BY public.waste_bombers.id;


--
-- Name: waters; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.waters (
    id bigint NOT NULL,
    event_schedule_id uuid NOT NULL,
    has_separate_meter boolean NOT NULL,
    start_meter integer,
    end_meter integer,
    start_meter_url character varying(255),
    end_meter_url character varying(255),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone
);


--
-- Name: water_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.water_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: water_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.water_id_seq OWNED BY public.waters.id;


--
-- Name: airports id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.airports ALTER COLUMN id SET DEFAULT nextval('public.airports_id_seq'::regclass);


--
-- Name: electricities id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.electricities ALTER COLUMN id SET DEFAULT nextval('public.electricity_id_seq'::regclass);


--
-- Name: flight_routes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.flight_routes ALTER COLUMN id SET DEFAULT nextval('public.flight_routes_id_seq'::regclass);


--
-- Name: food_and_beverages id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.food_and_beverages ALTER COLUMN id SET DEFAULT nextval('public.food_and_beverage_id_seq'::regclass);


--
-- Name: survey_utilities id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.survey_utilities ALTER COLUMN id SET DEFAULT nextval('public.survey_utilities_id_seq'::regclass);


--
-- Name: waste_bombers id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.waste_bombers ALTER COLUMN id SET DEFAULT nextval('public.waste_bomber_id_seq'::regclass);


--
-- Name: waters id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.waters ALTER COLUMN id SET DEFAULT nextval('public.water_id_seq'::regclass);


--
-- Name: airports airports_iata_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.airports
    ADD CONSTRAINT airports_iata_code_key UNIQUE (iata_code);


--
-- Name: airports airports_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.airports
    ADD CONSTRAINT airports_pkey PRIMARY KEY (id);


--
-- Name: booth_pricing_tiers booth_pricing_tiers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.booth_pricing_tiers
    ADD CONSTRAINT booth_pricing_tiers_pkey PRIMARY KEY (id);


--
-- Name: carbon_categories carbon_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.carbon_categories
    ADD CONSTRAINT carbon_categories_pkey PRIMARY KEY (id);


--
-- Name: carbon_credits carbon_credits_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.carbon_credits
    ADD CONSTRAINT carbon_credits_pkey PRIMARY KEY (id);


--
-- Name: carbon_emission_factors carbon_emission_factors_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.carbon_emission_factors
    ADD CONSTRAINT carbon_emission_factors_pkey PRIMARY KEY (id);


--
-- Name: carbon_emissions carbon_emissions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.carbon_emissions
    ADD CONSTRAINT carbon_emissions_pkey PRIMARY KEY (id);


--
-- Name: carbon_offset_pricing_tiers carbon_offset_pricing_tiers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.carbon_offset_pricing_tiers
    ADD CONSTRAINT carbon_offset_pricing_tiers_pkey PRIMARY KEY (id);


--
-- Name: carbon_offset_sources carbon_offset_sources_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.carbon_offset_sources
    ADD CONSTRAINT carbon_offset_sources_pkey PRIMARY KEY (id);


--
-- Name: carbon_scopes carbon_scopes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.carbon_scopes
    ADD CONSTRAINT carbon_scopes_pkey PRIMARY KEY (id);


--
-- Name: customers_quotations customers_quotations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers_quotations
    ADD CONSTRAINT customers_quotations_pkey PRIMARY KEY (id);


--
-- Name: customers_quotations customers_quotations_quotation_no_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers_quotations
    ADD CONSTRAINT customers_quotations_quotation_no_key UNIQUE (quotation_no);


--
-- Name: dashboard_images dashboard_images_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_images
    ADD CONSTRAINT dashboard_images_pkey PRIMARY KEY (id);


--
-- Name: dashboards dashboards_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboards
    ADD CONSTRAINT dashboards_pkey PRIMARY KEY (id);


--
-- Name: electricities electricity_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.electricities
    ADD CONSTRAINT electricity_pkey PRIMARY KEY (id);


--
-- Name: email_verifications email_verifications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_verifications
    ADD CONSTRAINT email_verifications_pkey PRIMARY KEY (id);


--
-- Name: event_accommodations event_accommodations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_accommodations
    ADD CONSTRAINT event_accommodations_pkey PRIMARY KEY (id);


--
-- Name: event_agencies event_agencies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_agencies
    ADD CONSTRAINT event_agencies_pkey PRIMARY KEY (id);


--
-- Name: event_api_key event_api_key_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_api_key
    ADD CONSTRAINT event_api_key_pkey PRIMARY KEY (id);


--
-- Name: event_certificate_issuers event_certificate_issuers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_certificate_issuers
    ADD CONSTRAINT event_certificate_issuers_pkey PRIMARY KEY (id);


--
-- Name: event_create_render_items event_create_render_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_create_render_items
    ADD CONSTRAINT event_create_render_items_pkey PRIMARY KEY (id);


--
-- Name: event_customer_contacts event_customer_contacts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_customer_contacts
    ADD CONSTRAINT event_customer_contacts_pkey PRIMARY KEY (id);


--
-- Name: event_documents event_documents_file_key_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_documents
    ADD CONSTRAINT event_documents_file_key_key UNIQUE (file_key);


--
-- Name: event_documents event_documents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_documents
    ADD CONSTRAINT event_documents_pkey PRIMARY KEY (id);


--
-- Name: event_exhibition_booths event_exhibition_booths_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_exhibition_booths
    ADD CONSTRAINT event_exhibition_booths_pkey PRIMARY KEY (id);


--
-- Name: event_giveaways event_giveaways_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_giveaways
    ADD CONSTRAINT event_giveaways_pkey PRIMARY KEY (id);


--
-- Name: event_images event_images_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_images
    ADD CONSTRAINT event_images_pkey PRIMARY KEY (id);


--
-- Name: event_item_and_giveaway_item_subtypes event_item_and_giveaway_item_subtypes_identifier_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_item_and_giveaway_item_subtypes
    ADD CONSTRAINT event_item_and_giveaway_item_subtypes_identifier_key UNIQUE (identifier);


--
-- Name: event_item_and_giveaway_item_subtypes event_item_and_giveaway_item_subtypes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_item_and_giveaway_item_subtypes
    ADD CONSTRAINT event_item_and_giveaway_item_subtypes_pkey PRIMARY KEY (id);


--
-- Name: event_item_and_giveaway_item_types event_item_and_giveaway_item_types_identifier_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_item_and_giveaway_item_types
    ADD CONSTRAINT event_item_and_giveaway_item_types_identifier_key UNIQUE (identifier);


--
-- Name: event_item_and_giveaway_item_types event_item_and_giveaway_item_types_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_item_and_giveaway_item_types
    ADD CONSTRAINT event_item_and_giveaway_item_types_pkey PRIMARY KEY (id);


--
-- Name: event_item_and_giveaway_item_units event_item_and_giveaway_item_units_identifier_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_item_and_giveaway_item_units
    ADD CONSTRAINT event_item_and_giveaway_item_units_identifier_key UNIQUE (identifier);


--
-- Name: event_item_and_giveaway_item_units event_item_and_giveaway_item_units_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_item_and_giveaway_item_units
    ADD CONSTRAINT event_item_and_giveaway_item_units_pkey PRIMARY KEY (id);


--
-- Name: event_item_and_giveaway_material_types event_item_and_giveaway_material_types_identifier_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_item_and_giveaway_material_types
    ADD CONSTRAINT event_item_and_giveaway_material_types_identifier_key UNIQUE (identifier);


--
-- Name: event_item_and_giveaway_material_types event_item_and_giveaway_material_types_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_item_and_giveaway_material_types
    ADD CONSTRAINT event_item_and_giveaway_material_types_pkey PRIMARY KEY (id);


--
-- Name: event_item_and_giveaways event_item_and_giveaways_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_item_and_giveaways
    ADD CONSTRAINT event_item_and_giveaways_pkey PRIMARY KEY (id);


--
-- Name: event_items event_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_items
    ADD CONSTRAINT event_items_pkey PRIMARY KEY (id);


--
-- Name: event_items_sub_types event_items_sub_types_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_items_sub_types
    ADD CONSTRAINT event_items_sub_types_pkey PRIMARY KEY (id);


--
-- Name: event_locations event_locations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_locations
    ADD CONSTRAINT event_locations_pkey PRIMARY KEY (id);


--
-- Name: event_orders event_orders_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_orders
    ADD CONSTRAINT event_orders_pkey PRIMARY KEY (id);


--
-- Name: event_pricing_tiers event_pricing_tiers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_pricing_tiers
    ADD CONSTRAINT event_pricing_tiers_pkey PRIMARY KEY (id);


--
-- Name: event_schedules event_schedules_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_schedules
    ADD CONSTRAINT event_schedules_pkey PRIMARY KEY (id);


--
-- Name: event_statuses event_statuses_name_eng_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_statuses
    ADD CONSTRAINT event_statuses_name_eng_key UNIQUE (name_eng);


--
-- Name: event_statuses event_statuses_name_thai_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_statuses
    ADD CONSTRAINT event_statuses_name_thai_key UNIQUE (name_thai);


--
-- Name: event_statuses event_statuses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_statuses
    ADD CONSTRAINT event_statuses_pkey PRIMARY KEY (id);


--
-- Name: event_statuses event_statuses_running_order_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_statuses
    ADD CONSTRAINT event_statuses_running_order_key UNIQUE (running_order);


--
-- Name: event_tax_invoices event_tax_invoices_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_tax_invoices
    ADD CONSTRAINT event_tax_invoices_pkey PRIMARY KEY (id);


--
-- Name: event_templates event_templates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_templates
    ADD CONSTRAINT event_templates_pkey PRIMARY KEY (id);


--
-- Name: event_types event_types_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_types
    ADD CONSTRAINT event_types_pkey PRIMARY KEY (id);


--
-- Name: events events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events
    ADD CONSTRAINT events_pkey PRIMARY KEY (id);


--
-- Name: exhibition_booth_options exhibition_booth_options_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exhibition_booth_options
    ADD CONSTRAINT exhibition_booth_options_pkey PRIMARY KEY (id);


--
-- Name: flight_routes flight_routes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.flight_routes
    ADD CONSTRAINT flight_routes_pkey PRIMARY KEY (id);


--
-- Name: food_and_beverages food_and_beverage_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.food_and_beverages
    ADD CONSTRAINT food_and_beverage_pkey PRIMARY KEY (id);


--
-- Name: form_template form_template_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.form_template
    ADD CONSTRAINT form_template_pkey PRIMARY KEY (id);


--
-- Name: forms forms_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.forms
    ADD CONSTRAINT forms_pkey PRIMARY KEY (id);


--
-- Name: goose_db_version goose_db_version_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.goose_db_version
    ADD CONSTRAINT goose_db_version_pkey PRIMARY KEY (id);


--
-- Name: international_to_thailand_distances international_to_thailand_distances_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.international_to_thailand_distances
    ADD CONSTRAINT international_to_thailand_distances_pkey PRIMARY KEY (id);


--
-- Name: survey_settings pk_survey_settings; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.survey_settings
    ADD CONSTRAINT pk_survey_settings PRIMARY KEY (survey_id, user_type);


--
-- Name: precal_snapshots precal_snapshots_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.precal_snapshots
    ADD CONSTRAINT precal_snapshots_pkey PRIMARY KEY (id);


--
-- Name: province_road_distances province_road_distances_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.province_road_distances
    ADD CONSTRAINT province_road_distances_pkey PRIMARY KEY (id);


--
-- Name: short_links short_links_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.short_links
    ADD CONSTRAINT short_links_code_key UNIQUE (code);


--
-- Name: short_links short_links_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.short_links
    ADD CONSTRAINT short_links_pkey PRIMARY KEY (id);


--
-- Name: survey_answers survey_answers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.survey_answers
    ADD CONSTRAINT survey_answers_pkey PRIMARY KEY (id);


--
-- Name: survey_participation_dates survey_participation_dates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.survey_participation_dates
    ADD CONSTRAINT survey_participation_dates_pkey PRIMARY KEY (id);


--
-- Name: surveys survey_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.surveys
    ADD CONSTRAINT survey_pkey PRIMARY KEY (id);


--
-- Name: survey_utilities survey_utilities_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.survey_utilities
    ADD CONSTRAINT survey_utilities_pkey PRIMARY KEY (id);


--
-- Name: tgo_registration_submissions tgo_registration_submissions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tgo_registration_submissions
    ADD CONSTRAINT tgo_registration_submissions_pkey PRIMARY KEY (id);


--
-- Name: units units_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.units
    ADD CONSTRAINT units_pkey PRIMARY KEY (id);


--
-- Name: flight_routes uq_flight_route_origin_destination; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.flight_routes
    ADD CONSTRAINT uq_flight_route_origin_destination UNIQUE (origin_airport_id, destination_airport_id);


--
-- Name: short_links uq_short_links_target; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.short_links
    ADD CONSTRAINT uq_short_links_target UNIQUE (event_id, survey_id, page_type);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: waste_bombers waste_bomber_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.waste_bombers
    ADD CONSTRAINT waste_bomber_pkey PRIMARY KEY (id);


--
-- Name: waters water_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.waters
    ADD CONSTRAINT water_pkey PRIMARY KEY (id);


--
-- Name: carbon_emission_factors_identifier_uidx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX carbon_emission_factors_identifier_uidx ON public.carbon_emission_factors USING btree (identifier) WHERE (identifier IS NOT NULL);


--
-- Name: idx_customers_quotations_deleted_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_customers_quotations_deleted_at ON public.customers_quotations USING btree (deleted_at);


--
-- Name: idx_customers_quotations_email; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_customers_quotations_email ON public.customers_quotations USING btree (email);


--
-- Name: idx_customers_quotations_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_customers_quotations_event_id ON public.customers_quotations USING btree (event_id);


--
-- Name: idx_customers_quotations_legacy_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_customers_quotations_legacy_id ON public.customers_quotations USING btree (legacy_id);


--
-- Name: idx_customers_quotations_quotation_no; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_customers_quotations_quotation_no ON public.customers_quotations USING btree (quotation_no);


--
-- Name: idx_event_documents_category; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_event_documents_category ON public.event_documents USING btree (category);


--
-- Name: idx_event_documents_deleted_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_event_documents_deleted_at ON public.event_documents USING btree (deleted_at);


--
-- Name: idx_event_documents_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_event_documents_event_id ON public.event_documents USING btree (event_id);


--
-- Name: idx_event_documents_event_id_slot_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_event_documents_event_id_slot_unique ON public.event_documents USING btree (event_id, slot) WHERE ((slot IS NOT NULL) AND (deleted_at IS NULL));


--
-- Name: idx_tgo_subs_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tgo_subs_event_id ON public.tgo_registration_submissions USING btree (event_id);


--
-- Name: idx_tgo_subs_sent_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tgo_subs_sent_at ON public.tgo_registration_submissions USING btree (sent_at DESC);


--
-- Name: idx_tgo_subs_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tgo_subs_status ON public.tgo_registration_submissions USING btree (status);


--
-- Name: idx_tgo_subs_tax_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tgo_subs_tax_id ON public.tgo_registration_submissions USING btree (tax_id);


--
-- Name: ix_event_api_key_event_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_event_api_key_event_active ON public.event_api_key USING btree (event_id, is_active);


--
-- Name: unique_schedule_not_deleted; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX unique_schedule_not_deleted ON public.event_schedules USING btree (event_id, start_date_time, end_date_time) WHERE (deleted_at IS NULL);


--
-- Name: uq_customers_quotations_event_id_active; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_customers_quotations_event_id_active ON public.customers_quotations USING btree (event_id) WHERE (deleted_at IS NULL);


--
-- Name: ux_event_api_key_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_event_api_key_hash ON public.event_api_key USING btree (key_hash);


--
-- Name: booth_pricing_tiers booth_pricing_tiers_event_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.booth_pricing_tiers
    ADD CONSTRAINT booth_pricing_tiers_event_type_id_fkey FOREIGN KEY (event_type_id) REFERENCES public.event_types(id);


--
-- Name: carbon_categories carbon_categories_carbon_scope_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.carbon_categories
    ADD CONSTRAINT carbon_categories_carbon_scope_id_fkey FOREIGN KEY (carbon_scope_id) REFERENCES public.carbon_scopes(id);


--
-- Name: carbon_credits carbon_credits_carbon_offset_source_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.carbon_credits
    ADD CONSTRAINT carbon_credits_carbon_offset_source_id_fkey FOREIGN KEY (carbon_offset_source_id) REFERENCES public.carbon_offset_sources(id);


--
-- Name: carbon_credits carbon_credits_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.carbon_credits
    ADD CONSTRAINT carbon_credits_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: carbon_emission_factors carbon_emission_factors_carbon_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.carbon_emission_factors
    ADD CONSTRAINT carbon_emission_factors_carbon_category_id_fkey FOREIGN KEY (carbon_category_id) REFERENCES public.carbon_categories(id);


--
-- Name: carbon_emission_factors carbon_emission_factors_unit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.carbon_emission_factors
    ADD CONSTRAINT carbon_emission_factors_unit_id_fkey FOREIGN KEY (unit_id) REFERENCES public.units(id);


--
-- Name: carbon_emissions carbon_emissions_carbon_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.carbon_emissions
    ADD CONSTRAINT carbon_emissions_carbon_category_id_fkey FOREIGN KEY (carbon_category_id) REFERENCES public.carbon_categories(id);


--
-- Name: carbon_emissions carbon_emissions_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.carbon_emissions
    ADD CONSTRAINT carbon_emissions_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.events(id);


--
-- Name: carbon_emissions carbon_emissions_unit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.carbon_emissions
    ADD CONSTRAINT carbon_emissions_unit_id_fkey FOREIGN KEY (unit_id) REFERENCES public.units(id);


--
-- Name: carbon_offset_pricing_tiers carbon_offset_pricing_tiers_carbon_offset_source_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.carbon_offset_pricing_tiers
    ADD CONSTRAINT carbon_offset_pricing_tiers_carbon_offset_source_id_fkey FOREIGN KEY (carbon_offset_source_id) REFERENCES public.carbon_offset_sources(id);


--
-- Name: carbon_offset_pricing_tiers carbon_offset_pricing_tiers_unit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.carbon_offset_pricing_tiers
    ADD CONSTRAINT carbon_offset_pricing_tiers_unit_id_fkey FOREIGN KEY (unit_id) REFERENCES public.units(id);


--
-- Name: dashboard_images dashboard_images_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_images
    ADD CONSTRAINT dashboard_images_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.events(id) ON DELETE CASCADE;


--
-- Name: dashboards dashboards_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboards
    ADD CONSTRAINT dashboards_id_fkey FOREIGN KEY (id) REFERENCES public.events(id) ON DELETE CASCADE;


--
-- Name: electricities electricity_event_schedule_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.electricities
    ADD CONSTRAINT electricity_event_schedule_id_fkey FOREIGN KEY (event_schedule_id) REFERENCES public.event_schedules(id) ON DELETE CASCADE;


--
-- Name: email_verifications email_verifications_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_verifications
    ADD CONSTRAINT email_verifications_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.events(id);


--
-- Name: event_accommodations event_accommodations_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_accommodations
    ADD CONSTRAINT event_accommodations_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.events(id);


--
-- Name: event_agencies event_agencies_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_agencies
    ADD CONSTRAINT event_agencies_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.events(id);


--
-- Name: event_certificate_issuers event_certificate_issuers_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_certificate_issuers
    ADD CONSTRAINT event_certificate_issuers_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.events(id);


--
-- Name: event_create_render_items event_create_render_items_item_subtype_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_create_render_items
    ADD CONSTRAINT event_create_render_items_item_subtype_id_fkey FOREIGN KEY (item_subtype_id) REFERENCES public.event_item_and_giveaway_item_subtypes(id);


--
-- Name: event_create_render_items event_create_render_items_item_unit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_create_render_items
    ADD CONSTRAINT event_create_render_items_item_unit_id_fkey FOREIGN KEY (item_unit_id) REFERENCES public.event_item_and_giveaway_item_units(id);


--
-- Name: event_customer_contacts event_customer_contacts_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_customer_contacts
    ADD CONSTRAINT event_customer_contacts_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.events(id);


--
-- Name: event_documents event_documents_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_documents
    ADD CONSTRAINT event_documents_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.events(id);


--
-- Name: event_exhibition_booths event_exhibition_booths_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_exhibition_booths
    ADD CONSTRAINT event_exhibition_booths_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.events(id);


--
-- Name: event_exhibition_booths event_exhibition_booths_unit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_exhibition_booths
    ADD CONSTRAINT event_exhibition_booths_unit_id_fkey FOREIGN KEY (unit_id) REFERENCES public.units(id);


--
-- Name: event_giveaways event_giveaways_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_giveaways
    ADD CONSTRAINT event_giveaways_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.events(id);


--
-- Name: event_images event_images_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_images
    ADD CONSTRAINT event_images_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.events(id);


--
-- Name: event_item_and_giveaway_item_subtypes event_item_and_giveaway_item_subtypes_item_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_item_and_giveaway_item_subtypes
    ADD CONSTRAINT event_item_and_giveaway_item_subtypes_item_type_id_fkey FOREIGN KEY (item_type_id) REFERENCES public.event_item_and_giveaway_item_types(id);


--
-- Name: event_item_and_giveaway_item_subtypes event_item_and_giveaway_item_subtypes_material_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_item_and_giveaway_item_subtypes
    ADD CONSTRAINT event_item_and_giveaway_item_subtypes_material_type_id_fkey FOREIGN KEY (material_type_id) REFERENCES public.event_item_and_giveaway_material_types(id);


--
-- Name: event_item_and_giveaway_material_types event_item_and_giveaway_material_types_emission_factor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_item_and_giveaway_material_types
    ADD CONSTRAINT event_item_and_giveaway_material_types_emission_factor_id_fkey FOREIGN KEY (emission_factor_id) REFERENCES public.carbon_emission_factors(id);


--
-- Name: event_item_and_giveaways event_item_and_giveaways_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_item_and_giveaways
    ADD CONSTRAINT event_item_and_giveaways_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.events(id);


--
-- Name: event_item_and_giveaways event_item_and_giveaways_item_material_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_item_and_giveaways
    ADD CONSTRAINT event_item_and_giveaways_item_material_id_fkey FOREIGN KEY (item_material_id) REFERENCES public.event_item_and_giveaway_material_types(id);


--
-- Name: event_item_and_giveaways event_item_and_giveaways_item_subtype_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_item_and_giveaways
    ADD CONSTRAINT event_item_and_giveaways_item_subtype_id_fkey FOREIGN KEY (item_subtype_id) REFERENCES public.event_item_and_giveaway_item_subtypes(id);


--
-- Name: event_item_and_giveaways event_item_and_giveaways_item_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_item_and_giveaways
    ADD CONSTRAINT event_item_and_giveaways_item_type_id_fkey FOREIGN KEY (item_type_id) REFERENCES public.event_item_and_giveaway_item_types(id);


--
-- Name: event_item_and_giveaways event_item_and_giveaways_item_unit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_item_and_giveaways
    ADD CONSTRAINT event_item_and_giveaways_item_unit_id_fkey FOREIGN KEY (item_unit_id) REFERENCES public.event_item_and_giveaway_item_units(id);


--
-- Name: event_items event_items_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_items
    ADD CONSTRAINT event_items_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.events(id);


--
-- Name: event_items_sub_types event_items_sub_types_event_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_items_sub_types
    ADD CONSTRAINT event_items_sub_types_event_item_id_fkey FOREIGN KEY (event_item_id) REFERENCES public.event_items(id);


--
-- Name: event_locations event_locations_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_locations
    ADD CONSTRAINT event_locations_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.events(id);


--
-- Name: event_orders event_orders_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_orders
    ADD CONSTRAINT event_orders_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.events(id);


--
-- Name: event_schedules event_schedules_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_schedules
    ADD CONSTRAINT event_schedules_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.events(id);


--
-- Name: event_tax_invoices event_tax_invoices_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_tax_invoices
    ADD CONSTRAINT event_tax_invoices_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.events(id);


--
-- Name: event_templates event_templates_event_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_templates
    ADD CONSTRAINT event_templates_event_type_id_fkey FOREIGN KEY (event_type_id) REFERENCES public.event_types(id);


--
-- Name: events events_carbon_offset_source_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events
    ADD CONSTRAINT events_carbon_offset_source_id_fkey FOREIGN KEY (carbon_offset_source_id) REFERENCES public.carbon_offset_sources(id);


--
-- Name: events events_event_template_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events
    ADD CONSTRAINT events_event_template_id_fkey FOREIGN KEY (event_template_id) REFERENCES public.event_templates(id);


--
-- Name: exhibition_booth_options exhibition_booth_options_unit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exhibition_booth_options
    ADD CONSTRAINT exhibition_booth_options_unit_id_fkey FOREIGN KEY (unit_id) REFERENCES public.units(id);


--
-- Name: customers_quotations fk_customers_quotations_event; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers_quotations
    ADD CONSTRAINT fk_customers_quotations_event FOREIGN KEY (event_id) REFERENCES public.events(id) ON DELETE CASCADE;


--
-- Name: event_api_key fk_event_api_key_event; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_api_key
    ADD CONSTRAINT fk_event_api_key_event FOREIGN KEY (event_id) REFERENCES public.events(id);


--
-- Name: survey_answers fk_survey_survey_answer; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.survey_answers
    ADD CONSTRAINT fk_survey_survey_answer FOREIGN KEY (survey_id) REFERENCES public.surveys(id);


--
-- Name: survey_settings fk_survey_survey_settings; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.survey_settings
    ADD CONSTRAINT fk_survey_survey_settings FOREIGN KEY (survey_id) REFERENCES public.surveys(id);


--
-- Name: flight_routes flight_routes_destination_airport_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.flight_routes
    ADD CONSTRAINT flight_routes_destination_airport_id_fkey FOREIGN KEY (destination_airport_id) REFERENCES public.airports(id);


--
-- Name: flight_routes flight_routes_origin_airport_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.flight_routes
    ADD CONSTRAINT flight_routes_origin_airport_id_fkey FOREIGN KEY (origin_airport_id) REFERENCES public.airports(id);


--
-- Name: food_and_beverages food_and_beverage_event_schedule_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.food_and_beverages
    ADD CONSTRAINT food_and_beverage_event_schedule_id_fkey FOREIGN KEY (event_schedule_id) REFERENCES public.event_schedules(id) ON DELETE CASCADE;


--
-- Name: forms forms_form_template_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.forms
    ADD CONSTRAINT forms_form_template_id_fkey FOREIGN KEY (form_template_id) REFERENCES public.form_template(id);


--
-- Name: precal_snapshots precal_snapshots_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.precal_snapshots
    ADD CONSTRAINT precal_snapshots_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.events(id);


--
-- Name: short_links short_links_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.short_links
    ADD CONSTRAINT short_links_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.events(id) ON DELETE CASCADE;


--
-- Name: short_links short_links_survey_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.short_links
    ADD CONSTRAINT short_links_survey_id_fkey FOREIGN KEY (survey_id) REFERENCES public.surveys(id) ON DELETE CASCADE;


--
-- Name: surveys survey_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.surveys
    ADD CONSTRAINT survey_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.events(id) ON DELETE CASCADE;


--
-- Name: survey_participation_dates survey_participation_dates_survey_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.survey_participation_dates
    ADD CONSTRAINT survey_participation_dates_survey_id_fkey FOREIGN KEY (survey_answer_id) REFERENCES public.survey_answers(id) ON DELETE CASCADE;


--
-- Name: survey_utilities survey_utilities_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.survey_utilities
    ADD CONSTRAINT survey_utilities_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.events(id) ON DELETE CASCADE;


--
-- Name: tgo_registration_submissions tgo_registration_submissions_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tgo_registration_submissions
    ADD CONSTRAINT tgo_registration_submissions_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.events(id);


--
-- Name: waste_bombers waste_bomber_event_schedule_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.waste_bombers
    ADD CONSTRAINT waste_bomber_event_schedule_id_fkey FOREIGN KEY (event_schedule_id) REFERENCES public.event_schedules(id) ON DELETE CASCADE;


--
-- Name: waters water_event_schedule_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.waters
    ADD CONSTRAINT water_event_schedule_id_fkey FOREIGN KEY (event_schedule_id) REFERENCES public.event_schedules(id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--


