RSpec.describe ActiveRecord::VirtualAttributes::VirtualDelegates, :with_test_class do
  # double purposing col1. It has an actual value in the child class
  let(:parent) { TestClass.create(:col1 => 4) }

  it "delegates to parent" do
    TestClass.virtual_delegate :col1, :prefix => 'parent', :to => :ref1, :type => :integer
    tc = TestClass.new(:ref1 => parent)
    expect(tc.parent_col1).to eq(4)
  end

  it "delegates to nil parent" do
    TestClass.virtual_delegate :col1, :prefix => 'parent', :to => :ref1, :allow_nil => true, :type => :integer
    tc = TestClass.new
    expect(tc.parent_col1).to be_nil
  end

  it "defines parent virtual attribute" do
    TestClass.virtual_delegate :col1, :prefix => 'parent', :to => :ref1, :type => :integer
    expect(TestClass.virtual_attribute_names).to include("parent_col1")
  end

  it "delegates to parent (sql)" do
    TestClass.virtual_delegate :col1, :prefix => 'parent', :to => :ref1, :type => :integer
    TestClass.create(:ref1 => parent)
    tcs = TestClass.select(:id, :col1, TestClass.arel_table[:parent_col1].as("x"))
    expect(tcs.map(&:x)).to match_array([nil, 4])
  end

  # NOTE: this is intentonally delegating to self. Testing table aliases
  it "double delegates to parent information" do
    g = Author.create(:name => "grand")
    p = Author.create(:name => "parent", :teacher_id => g.id)
    Author.create(:name => "c1", :teacher_id => p.id)
    Author.create(:name => "c2", :teacher_id => p.id)

    ret = Author.select(:name, :teacher_teacher_name, :teacher_name).order(:id).where(:teacher_id => p.id)
    expect(ret.map { |c| [c.teacher_teacher_name, c.teacher_name, c.name] }).to eq([["grand", "parent", "c1"], ["grand", "parent", "c2"]])
  end

  context "invalid" do
    it "expects a ':to' for delegation" do
      expect do
        TestClass.virtual_delegate :col1, :type => :integer
      end.to raise_error(ArgumentError, /missing keyword: :to/)
    end

    it "expects a ':type' for delegation" do
      expect do
        TestClass.virtual_delegate :col1, :to => :ref1
        TestClass.new
      end.to raise_error(ArgumentError, /missing keyword: :type/)
    end

    it "only allows 1 method when delegating to a specific method" do
      expect do
        TestClass.virtual_delegate :col1, :col2, :to => "ref1.method", :type => :string
      end.to raise_error(ArgumentError, /single virtual method/)
    end

    it "only allows 1 level deep delegation" do
      expect do
        TestClass.virtual_delegate :col1, :to => "ref1.method.method2", :type => :string
      end.to raise_error(ArgumentError, /single association/)
    end

    it "detects invalid destination" do
      expect do
        TestClass.virtual_delegate :col1, :to => "bogus_ref.method", :type => :string
        TestClass.new
      end.to raise_error(ArgumentError, /needs an association/)
    end
  end

  context "with has_one :parent" do
    before do
      TestClass.has_one :ref2, :class_name => 'TestClass', :foreign_key => :col1, :inverse_of => :ref1
    end
    # child.col1 will be getting parent's (aka tc's) id
    let(:child) { TestClass.create }

    it "delegates to child" do
      TestClass.virtual_delegate :col1, :prefix => 'child', :to => :ref2, :type => :integer
      tc = TestClass.create(:ref2 => child)
      expect(tc.child_col1).to eq(tc.id)
    end

    it "delegates to nil child" do
      TestClass.virtual_delegate :col1, :prefix => 'child', :to => :ref2, :allow_nil => true, :type => :integer
      tc = TestClass.new
      expect(tc.child_col1).to be_nil
    end

    it "defines child virtual attribute" do
      TestClass.virtual_delegate :col1, :prefix => 'child', :to => :ref2, :type => :integer
      expect(TestClass.virtual_attribute_names).to include("child_col1")
    end

    it "delegates to child (sql)" do
      TestClass.virtual_delegate :col1, :prefix => 'child', :to => :ref2, :type => :integer
      tc = TestClass.create(:ref2 => child)
      tcs = TestClass.select(:id, :col1, :child_col1).to_a
      expect { expect(tcs.map(&:child_col1)).to match_array([nil, tc.id]) }.to_not make_database_queries
    end

    # this may fail in the future as our way of building queries may change
    # just want to make sure it changed due to intentional changes
    it "uses table alias for subquery" do
      TestClass.virtual_delegate :col1, :prefix => 'child', :to => :ref2, :type => :integer
      sql = TestClass.select(:id, :col1, :child_col1).to_sql
      expect(sql).to match(/["`]test_classes_[^"`]*["`][.]["`]col1["`]/i)
    end
  end

  context "with self join has_one and select" do
    before do
      TestClass.has_one :ref2, -> { select(:col1) }, :class_name => 'TestClass', :foreign_key => :col1
    end
    # child.col1 will be getting parent's (aka tc's) id
    let(:child) { TestClass.create }

    # ensure virtual attribute referencing a relation with a select()
    # does not throw an exception due to multi-column select
    it "properly generates sub select" do
      TestClass.virtual_delegate :col1, :prefix => 'child', :to => :ref2, :type => :integer
      TestClass.create(:ref2 => child)
      expect { TestClass.select(:id, :child_col1).to_a }.to_not raise_error
    end
  end

  context "with self join has_one and order (self join)" do
    before do
      # TODO: , -> { order(:col1) }
      TestClass.has_one :ref2, :class_name => 'TestClass', :foreign_key => :col1
    end
    # child.col1 will be getting parent's (aka tc's) id
    let(:child) { TestClass.create }

    # ensure virtual attribute referencing a relation with a select()
    # does not throw an exception due to multi-column select
    it "properly generates sub select" do
      TestClass.virtual_delegate :col1, :prefix => 'child', :to => :ref2, :type => :integer
      TestClass.create(:ref2 => child)
      expect { TestClass.select(:id, :child_col1).to_a }.to_not raise_error
    end
  end

  context "with has_one and order (and many records)" do
    before do
      # OperatingSystem (child)
      class TestOtherClass < ActiveRecord::Base # rubocop:disable Rails/ApplicationRecord
        def self.connection
          TestClassBase.connection
        end
        belongs_to :parent, :class_name => 'TestClass', :foreign_key => :ocol1

        include VirtualFields
      end
      # TODO: -> { order(:col1) }
      TestClass.has_one :child, :class_name => 'TestOtherClass', :foreign_key => :ocol1
      TestClass.virtual_delegate :child_str, :to => "child.ostr", :type => :string
    end

    after do
      Object.send(:remove_const, :TestOtherClass)
    end

    # ensure virtual attribute referencing a relation with has_one and order()
    # works properly
    it "properly generates sub select" do
      parent = TestClass.create(:str => "p")
      child1 = TestOtherClass.create(:parent => parent, :ostr => "c1")
      TestOtherClass.create(:parent => parent, :ostr => "c2")

      expect(TestClass.select(:id, :child_str).find_by(:id => parent.id).child_str).to eq(child1.ostr)
    end
  end

  context "with relation in foreign table" do
    before do
      class TestOtherClass < ActiveRecord::Base # rubocop:disable Rails/ApplicationRecord
        def self.connection
          TestClassBase.connection
        end
        belongs_to :oref1, :class_name => 'TestClass', :foreign_key => :ocol1

        include VirtualFields
      end
    end

    after do
      Object.send(:remove_const, :TestOtherClass)
    end

    it "delegates to another table" do
      TestOtherClass.virtual_delegate :col1, :to => :oref1, :type => :integer
      TestOtherClass.create(:oref1 => TestClass.create)
      TestOtherClass.create(:oref1 => TestClass.create(:col1 => 99))
      tcs = TestOtherClass.select(:id, :ocol1, TestOtherClass.arel_table[:col1].as("x"))
      expect(tcs.map(&:x)).to match_array([nil, 99])

      expect { tcs = TestOtherClass.select(:id, :ocol1, :col1).load }.to make_database_queries(:count => 1)
      expect(tcs.map(&:col1)).to match_array([nil, 99])
    end

    # this may fail in the future as our way of building queries may change
    # just want to make sure it changed due to intentional changes
    it "delegates to another table without alias" do
      TestOtherClass.virtual_delegate :col1, :to => :oref1, :type => :integer
      sql = TestOtherClass.select(:id, :ocol1, TestOtherClass.arel_table[:col1].as("x")).to_sql
      expect(sql).to match(/["`]test_classes["`].["`]col1["`]/i)
    end

    it "supports :type (and works when reference IS valid)" do
      TestOtherClass.virtual_delegate :col1, :to => :oref1, :type => :integer
      TestOtherClass.create(:oref1 => TestClass.create)
      TestOtherClass.create(:oref1 => TestClass.create(:col1 => 99))
      tcs = TestOtherClass.select(:id, :ocol1, TestOtherClass.arel_table[:col1].as("x"))
      expect(tcs.map(&:x)).to match_array([nil, 99])
    end

    it "detects bad reference" do
      TestOtherClass.virtual_delegate :bogus, :to => :oref1, :type => :integer
      expect { TestOtherClass.new }.not_to raise_error
      expect { TestOtherClass.new(:oref1 => TestClass.new).bogus }.to raise_error(NoMethodError)
    end

    it "detects bad reference in sql" do
      TestOtherClass.virtual_delegate :bogus, :to => :oref1, :type => :integer
      # any exception will do
      expect { TestOtherClass.select(:bogus).first }.to raise_error(ActiveRecord::StatementInvalid)
    end

    it "doesn't reference target class when :type is specified" do
      TestOtherClass.has_many :others, :class_name => "InvalidType"
      TestOtherClass.virtual_delegate :col4, :to => :others, :type => :integer

      # doesn't lookup InvalidType class with this model
      expect { TestOtherClass.new }.not_to raise_error
      # referencing the relation still accesses the model (which is invalid so blows up)
      expect { TestOtherClass.new.col4 }.to raise_error(NameError)
    end

    it "catches invalid references" do
      expect { TestOtherClass.virtual_delegate :col4, :to => :others, :type => :integer }.to raise_error(ArgumentError)
    end

    it "catches invalid column" do
      TestOtherClass.virtual_delegate :col4, :to => :oref1, :type => :integer

      expect { model.new }.to raise_error(NameError)
    end
  end

  context "with polymorphic has_one" do
    it "supports select" do
      author = Author.create(:name => "no one of consequence")
      author.photos.create(:description => 'good')

      author = Author.select(:id, :current_photo_description).find(author.id)
      expect(author.current_photo_description).to eq("good")
    end

    it "supports bind variables in association" do
      author = Author.create(:name => "no one of consequence")
      author.photos.create(:description => 'good', :purpose => "fancy")

      author = Author.select(:id, :fancy_photo_description).find(author.id)
      expect(author).to preload_values(:fancy_photo_description, "good")
    end

    it "respects type" do
      author = Author.create(:name => "no one of consequence")
      book = author.books.create(:name => "nothing of consequence", :id => author.id)
      book.photos.create(:description => 'bad')

      author = Author.select(:id, :current_photo_description).find(author.id)
      expect(author.current_photo_description).to eq(nil)
    end

    it "handles polymorphic in" do
      author = Author.create(:name => "no one of consequence")
      author.books.create(:name => "nothing of consequence", :id => author.id)
      author.photos.create(:description => 'good')

      actual = Author.where(:current_photo_description => %w[good ok]).find(author.id)
      expect(actual).to eq(author)
    end

    it "handles polymorphic or" do
      author = Author.create(:name => "no one of consequence")
      author.books.create(:name => "nothing of consequence", :id => author.id)
      author.photos.create(:description => 'good')

      # ensuring that the parens for delegates don't mess up sql
      actual = Author.where(:current_photo_description => "good")
                     .or(Author.where(:current_photo_description => "ok"))
                     .first
      expect(actual).to eq(author)
    end
  end

  describe "virtual_has_many with :through" do
    it "with :source works" do
      Author.create_with_books(2)
      author = Author.create_with_books(3)
      books = author.books.order(:id)

      expect(books.first.author_books.order(:id)).to eq(books)
    end

    it "without :source works" do
      Author.create_with_books(2)
      author = Author.create_with_books(3)
      books = author.books.order(:id)

      expect(books.first.books.order(:id)).to eq(books)
    end
  end

  describe "#determine_method_names (private)" do
    it "works with column and to" do
      expect(determine_method_names("column", "relation", nil)).to eq([:column, :relation, :column])
      expect(determine_method_names("column", "relation", true)).to eq([:relation_column, :relation, :column])
      expect(determine_method_names("column", "relation", "pre")).to eq([:pre_column, :relation, :column])
      expect(determine_method_names("column", "relation.column2", false)).to eq([:column, :relation, :column2])
      expect(determine_method_names("column", "relation.column2", true)).to eq([:relation_column, :relation, :column2])

      TestClass.virtual_delegate :str, :to => :ref1, :prefix => true, :type => :string
      expect(TestClass.new.respond_to?(:ref1_str)).to eq(true)

      expect do
        TestClass.virtual_delegate :my_method, :to => "ref1.str", :prefix => true, :type => :string
      end.to raise_exception(ArgumentError)
    end
  end

  def determine_method_names(*args)
    TestClass.send(:determine_method_names, *args)
  end
end
