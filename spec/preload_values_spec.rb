RSpec.describe "preloads_values" do
  before do
    Author.destroy_all
    Book.destroy_all
    Author.create_with_books(3).books.first.create_bookmarks(2)
  end

  let(:author_name) { "foo" }
  let(:book_name) { "bar" }

  it "detects preloaded values" do
    expect(Book.select(:author_name)).to preload_values(:author_name, [author_name, author_name, author_name])
  end

  it "detects preloaded values converts to array" do
    expect(Book.select(:author_name)).to preload_values(:author_name, author_name)
  end

  it "detects not preloaded" do
    expect do
      expect(Book).to preload_values(:author_name, author_name)
    end.to raise_error(RSpec::Expectations::ExpectationNotMetError, "Expected to preload author_name but executed 3 queries instead")
  end

  it "detects incorrect values" do
    expect do
      expect(Book.select(:author_name)).to preload_values(:author_name, "bogus")
    end.to raise_error(RSpec::Expectations::ExpectationNotMetError)
  end

  it "detects not preloading values" do
    expect(Book).not_to preload_values(:author_name, author_name)
  end

  # NOTE: was unsure if incorrect values met or failed the expectation
  # went with the core of the expectation is preloading. but matching values trumps all
  it "detects not preloading values (bad value)" do
    expect do
      expect(Book).not_to preload_values(:author_name, "bogus")
    end.to raise_error(RSpec::Expectations::ExpectationNotMetError)
  end

  it "detects not preloading values failure" do
    expect do
      expect(Book.select(:author_name)).not_to preload_values(:author_name, author_name)
    end.to raise_error(RSpec::Expectations::ExpectationNotMetError, "Unexpectedly preloaded author_name")
  end
end
