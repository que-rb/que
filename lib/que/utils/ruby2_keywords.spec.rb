# frozen_string_literal: true

require 'spec_helper'

describe Que::Utils::Ruby2Keywords do
  describe "split_out_ruby2_keywords" do
    describe "when last argument is not a hash" do
      let(:args_splat) { ["string"] }

      it "does not split arguments" do
        args, kwargs = Que.split_out_ruby2_keywords(args_splat)
        assert_equal(["string"], args)
        assert_equal({}, kwargs)
      end
    end

    describe "when last argument a hash literal" do
      let(:args_splat) { ["string", { a: 1, b: 2}] }

      it "does not split arguments" do
        args, kwargs = Que.split_out_ruby2_keywords(args_splat)
        assert_equal(["string", {a: 1, b: 2}], args)
        assert_equal({}, kwargs)
      end
    end

    describe "when last argument is flagged as a ruby2 keywords hash" do
      let(:args_splat) { ["string", Hash.ruby2_keywords_hash({ a: 1, b: 2})] }

      it "splits keywords out of arguments" do
        args, kwargs = Que.split_out_ruby2_keywords(args_splat)
        assert_equal(["string"], args)
        assert_equal({ a: 1, b: 2}, kwargs)
      end
    end
  end
end
