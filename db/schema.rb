# encoding: UTF-8
# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 20150602221628) do

  create_table "delayed_jobs", force: :cascade do |t|
    t.integer  "priority",   limit: 4,     default: 0, null: false
    t.integer  "attempts",   limit: 4,     default: 0, null: false
    t.text     "handler",    limit: 65535,             null: false
    t.text     "last_error", limit: 65535
    t.datetime "run_at"
    t.datetime "locked_at"
    t.datetime "failed_at"
    t.string   "locked_by",  limit: 255
    t.string   "queue",      limit: 255
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "delayed_jobs", ["priority", "run_at"], name: "delayed_jobs_priority", using: :btree

  create_table "migration_logs", force: :cascade do |t|
    t.integer  "log_type",         limit: 4
    t.integer  "migration_run_id", limit: 4
    t.string   "message",          limit: 255
    t.string   "source_id",        limit: 255
    t.string   "target_id",        limit: 255
    t.text     "target_before",    limit: 65535
    t.text     "target_after",     limit: 65535
    t.datetime "created_at",                     null: false
    t.datetime "updated_at",                     null: false
    t.text     "source_before",    limit: 65535
    t.text     "id_list",          limit: 65535
  end

  create_table "migration_runs", force: :cascade do |t|
    t.datetime "started_at"
    t.datetime "ended_at"
    t.integer  "source_system_id",      limit: 4
    t.integer  "destination_system_id", limit: 4
    t.integer  "user_id",               limit: 4
    t.string   "entity_type",           limit: 255
    t.integer  "records_migrated",      limit: 4
    t.integer  "max_records",           limit: 4
    t.integer  "status",                limit: 4,     default: 0
    t.string   "name",                  limit: 255
    t.datetime "created_at",                                      null: false
    t.datetime "updated_at",                                      null: false
    t.boolean  "all_records",           limit: 1
    t.text     "record_list",           limit: 65535
    t.integer  "phase",                 limit: 4
    t.datetime "abort_at"
    t.integer  "start_page",            limit: 4
    t.date     "from_date"
    t.date     "through_date"
  end

  create_table "systems", force: :cascade do |t|
    t.string   "name",             limit: 255
    t.string   "ref_url",          limit: 255
    t.datetime "created_at",                   null: false
    t.datetime "updated_at",                   null: false
    t.integer  "integration_type", limit: 4
  end

  create_table "users", force: :cascade do |t|
    t.string   "email",                  limit: 255, default: "", null: false
    t.string   "encrypted_password",     limit: 255, default: "", null: false
    t.string   "reset_password_token",   limit: 255
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.integer  "sign_in_count",          limit: 4,   default: 0,  null: false
    t.datetime "current_sign_in_at"
    t.datetime "last_sign_in_at"
    t.string   "current_sign_in_ip",     limit: 255
    t.string   "last_sign_in_ip",        limit: 255
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "users", ["email"], name: "index_users_on_email", unique: true, using: :btree
  add_index "users", ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true, using: :btree

end
