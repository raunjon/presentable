# frozen_string_literal: true

require "test_helper"

# GEM-4: columns a model hides (hide_from_api, or encrypted) must never be
# returned through ?fields=, even when named explicitly.
class ThirtyplusApi::HiddenAttributesTest < ActiveSupport::TestCase
  # Encrypts a column without including the concern, to prove encrypted
  # columns are hidden automatically.
  class EncryptedOnlyLead < ActiveRecord::Base
    self.table_name = "leads"
    encrypts :email
  end

  setup do
    @params = ActionController::Parameters.new
  end

  def unknown_fields_for(query, fields)
    @params[:fields] = fields
    error = assert_raises(ThirtyplusApi::FieldFilterService::UnknownFieldsError) do
      ThirtyplusApi::FieldFilterService.new(@params, query).call
    end
    error.fields
  end

  test "hidden_columns_for lists declared and encrypted columns" do
    assert_equal ["internal_notes", "access_code"], ThirtyplusApi::HiddenAttributes.hidden_columns_for(Venue)
  end

  test "hidden_columns_for is empty for a model that hides nothing" do
    assert_equal [], ThirtyplusApi::HiddenAttributes.hidden_columns_for(Event)
  end

  test "encrypted columns are hidden without including the concern" do
    assert_equal ["email"], ThirtyplusApi::HiddenAttributes.hidden_columns_for(EncryptedOnlyLead)
    assert_equal ["email"], unknown_fields_for(EncryptedOnlyLead.all, "id,email")
  end

  test "an encrypted column is rejected like an unknown field" do
    assert_equal ["access_code"], unknown_fields_for(Venue.all, "name,access_code")
  end

  test "a hide_from_api column is rejected like an unknown field" do
    assert_equal ["internal_notes"], unknown_fields_for(Venue.all, "name,internal_notes")
  end

  test "a hidden column is rejected through an association path" do
    assert_equal ["event.venue.access_code", "event.venue.internal_notes"],
                 unknown_fields_for(Lead.all, "id,event.venue.access_code,event.venue.internal_notes")
  end

  test "hidden columns are rejected on a single record too" do
    assert_equal ["internal_notes"], unknown_fields_for(Venue.new(id: 1), "internal_notes")
  end

  test "visible columns of a model with hidden columns still work" do
    @params[:fields] = "id,name"

    assert_nothing_raised { ThirtyplusApi::FieldFilterService.new(@params, Venue.all).call }
  end

  test "hide_from_api does not leak to other models" do
    refute Event.respond_to?(:api_hidden_attributes)
    assert_equal ["internal_notes"], Venue.api_hidden_attributes
  end
end
