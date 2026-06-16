module Persistence
  class ArEventRepository
    PAGE_SIZE = 25

    def find(id)
      Core::Event.kept.find(id)
    rescue ActiveRecord::RecordNotFound, ActiveRecord::StatementInvalid
      # StatementInvalid: malformed uuid strings must read as "not found",
      # not a 500 (lesson from the admin_users padded-id review).
      raise Ports::NotFound
    end

    def list(search: nil, status: nil, page: 1)
      scope = Core::Event.kept.order(created_at: :desc)
      if search.present?
        q = "%#{ActiveRecord::Base.sanitize_sql_like(search)}%"
        scope = scope.where("name_thai ILIKE :q OR name_eng ILIKE :q", q: q)
      end
      scope = scope.where(event_status: status) if status.present?
      page = [ page.to_i, 1 ].max
      scope.limit(PAGE_SIZE + 1).offset((page - 1) * PAGE_SIZE)
    end

    def update_status(id, to:, updated_by:)
      record = find(id)
      record.update!(event_status: to, updated_by: updated_by)
      record
    end

    # True if `code` is a real status in the event_statuses catalog (the same
    # set the dropdown is built from). events.event_status stores name_eng.
    def known_status?(code)
      Core::EventStatus.where(name_eng: code.to_s).exists?
    end

    def update_details(id, attrs, updated_by:)
      record = find(id)
      record.update!(**attrs, updated_by: updated_by)
      record
    rescue ActiveRecord::ValueTooLong
      raise Ports::ValidationFailed, "ข้อมูลยาวเกินขนาดที่อนุญาต (สูงสุด 255 ตัวอักษร)"
    rescue ActiveRecord::RecordInvalid => e
      raise Ports::ValidationFailed, e.record.errors.full_messages.to_sentence
    end

    # Permanent CASCADE delete. public.events is Go-owned with a multi-level FK
    # subtree (some children are RESTRICT, some already ON DELETE CASCADE, and a
    # few children have grandchildren). We cannot ON DELETE CASCADE the RESTRICT
    # constraints (that would alter the Go schema), so we replicate a cascade in
    # Ruby: walk the live FK graph from pg_constraint and delete every row that
    # transitively references this event, bottom-up, then the event — all in one
    # transaction. We only ever delete rows whose FK chains back to THIS event, so
    # the blast radius is exactly the event's own subtree. Any unexpected leftover
    # reference (e.g. a brand-new Go table) makes the final DELETE raise, the
    # transaction rolls back, and we surface a friendly failure (nothing deleted).
    MAX_CASCADE_DEPTH = 25

    def hard_delete_cascade(id)
      record = find(id)
      Core::Event.transaction { delete_subtree("public.events", "id", [ id ], 0) }
      record
    rescue ActiveRecord::InvalidForeignKey
      raise Ports::ValidationFailed, "ลบไม่สำเร็จ: ยังมีข้อมูลที่อ้างอิงอีเว้นท์นี้อยู่"
    end

    private

    # Deletes every descendant referencing `ids` (via tables' FKs to
    # `table`.`key_col`), grandchildren first, then the rows at this level.
    # All deletes go through AR's parameterized query builder — no string SQL.
    def delete_subtree(table, key_col, ids, depth)
      return if ids.empty?
      raise Ports::ValidationFailed, "โครงสร้างข้อมูลซับซ้อนเกินไป (cascade ลึกเกินกำหนด)" if depth > MAX_CASCADE_DEPTH

      fk_children(table).each do |child_table, fk_col|
        pk = primary_key_of(child_table)
        relation = ar_table(child_table).where(fk_col => ids)
        if pk
          child_ids = relation.pluck(pk)
          delete_subtree(child_table, pk, child_ids, depth + 1) unless child_ids.empty?
        end
        relation.delete_all
      end

      ar_table(table).where(key_col => ids).delete_all
    end

    # Anonymous AR model bound to a catalog-supplied table name, so the deletes
    # use AR's parameterized query builder rather than interpolated SQL.
    def ar_table(table)
      Class.new(ActiveRecord::Base) { self.table_name = table }
    end

    # [[child_table, fk_column], ...] for every single-column FK pointing at
    # `table`. Names come from the catalog (pg_constraint), not user input.
    def fk_children(table)
      conn = ActiveRecord::Base.connection
      conn.select_rows(<<~SQL).map { |child_table, fk_col| [ child_table, fk_col ] }
        SELECT con.conrelid::regclass::text, att.attname
        FROM pg_constraint con
        JOIN pg_attribute att ON att.attrelid = con.conrelid AND att.attnum = con.conkey[1]
        WHERE con.contype = 'f'
          AND array_length(con.conkey, 1) = 1
          AND con.confrelid = #{conn.quote(table)}::regclass
      SQL
    end

    def primary_key_of(table)
      conn = ActiveRecord::Base.connection
      conn.select_value(<<~SQL)
        SELECT att.attname FROM pg_index i
        JOIN pg_attribute att ON att.attrelid = i.indrelid AND att.attnum = ANY(i.indkey)
        WHERE i.indrelid = #{conn.quote(table)}::regclass AND i.indisprimary
        LIMIT 1
      SQL
    end
  end
end
