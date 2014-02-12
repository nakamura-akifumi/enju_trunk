require 'spec_helper'

# This spec was generated by rspec-rails when you ran the scaffold generator.
# It demonstrates how one might use RSpec to specify the controller code that
# was generated by Rails when you ran the scaffold generator.
#
# It assumes that the implementation code is generated by the rails scaffold
# generator.  If you are using any extension libraries to generate different
# controller code, this generated spec may or may not pass.
#
# It only uses APIs available in rails and/or rspec-rails.  There are a number
# of tools you can use to make these specs even more expressive, but we're
# sticking to rails and rspec-rails APIs to keep things simple and stable.
#
# Compared to earlier versions of this generator, there is very limited use of
# stubs and message expectations in this spec.  Stubs are only used when there
# is no simpler way to get a handle on the object needed for the example.
# Message expectations are only used when there is no simpler way to specify
# that an instance is receiving a specific message.

describe TitleTypesController do

  # This should return the minimal set of attributes required to create a valid
  # TitleType. As you add validations to TitleType, be sure to
  # adjust the attributes here as well.
  let(:valid_attributes) { { "id" => "1" } }

  # This should return the minimal set of values that should be in the session
  # in order to pass any filters (e.g. authentication) defined in
  # TitleTypesController. Be sure to keep this updated too.
  let(:valid_session) { {} }

  describe "GET index" do
    it "assigns all title_types as @title_types" do
      title_type = TitleType.create! valid_attributes
      get :index, {}, valid_session
      assigns(:title_types).should eq([title_type])
    end
  end

  describe "GET show" do
    it "assigns the requested title_type as @title_type" do
      title_type = TitleType.create! valid_attributes
      get :show, {:id => title_type.to_param}, valid_session
      assigns(:title_type).should eq(title_type)
    end
  end

  describe "GET new" do
    it "assigns a new title_type as @title_type" do
      get :new, {}, valid_session
      assigns(:title_type).should be_a_new(TitleType)
    end
  end

  describe "GET edit" do
    it "assigns the requested title_type as @title_type" do
      title_type = TitleType.create! valid_attributes
      get :edit, {:id => title_type.to_param}, valid_session
      assigns(:title_type).should eq(title_type)
    end
  end

  describe "POST create" do
    describe "with valid params" do
      it "creates a new TitleType" do
        expect {
          post :create, {:title_type => valid_attributes}, valid_session
        }.to change(TitleType, :count).by(1)
      end

      it "assigns a newly created title_type as @title_type" do
        post :create, {:title_type => valid_attributes}, valid_session
        assigns(:title_type).should be_a(TitleType)
        assigns(:title_type).should be_persisted
      end

      it "redirects to the created title_type" do
        post :create, {:title_type => valid_attributes}, valid_session
        response.should redirect_to(TitleType.last)
      end
    end

    describe "with invalid params" do
      it "assigns a newly created but unsaved title_type as @title_type" do
        # Trigger the behavior that occurs when invalid params are submitted
        TitleType.any_instance.stub(:save).and_return(false)
        post :create, {:title_type => { "id" => "invalid value" }}, valid_session
        assigns(:title_type).should be_a_new(TitleType)
      end

      it "re-renders the 'new' template" do
        # Trigger the behavior that occurs when invalid params are submitted
        TitleType.any_instance.stub(:save).and_return(false)
        post :create, {:title_type => { "id" => "invalid value" }}, valid_session
        response.should render_template("new")
      end
    end
  end

  describe "PUT update" do
    describe "with valid params" do
      it "updates the requested title_type" do
        title_type = TitleType.create! valid_attributes
        # Assuming there are no other title_types in the database, this
        # specifies that the TitleType created on the previous line
        # receives the :update_attributes message with whatever params are
        # submitted in the request.
        TitleType.any_instance.should_receive(:update_attributes).with({ "id" => "1" })
        put :update, {:id => title_type.to_param, :title_type => { "id" => "1" }}, valid_session
      end

      it "assigns the requested title_type as @title_type" do
        title_type = TitleType.create! valid_attributes
        put :update, {:id => title_type.to_param, :title_type => valid_attributes}, valid_session
        assigns(:title_type).should eq(title_type)
      end

      it "redirects to the title_type" do
        title_type = TitleType.create! valid_attributes
        put :update, {:id => title_type.to_param, :title_type => valid_attributes}, valid_session
        response.should redirect_to(title_type)
      end
    end

    describe "with invalid params" do
      it "assigns the title_type as @title_type" do
        title_type = TitleType.create! valid_attributes
        # Trigger the behavior that occurs when invalid params are submitted
        TitleType.any_instance.stub(:save).and_return(false)
        put :update, {:id => title_type.to_param, :title_type => { "id" => "invalid value" }}, valid_session
        assigns(:title_type).should eq(title_type)
      end

      it "re-renders the 'edit' template" do
        title_type = TitleType.create! valid_attributes
        # Trigger the behavior that occurs when invalid params are submitted
        TitleType.any_instance.stub(:save).and_return(false)
        put :update, {:id => title_type.to_param, :title_type => { "id" => "invalid value" }}, valid_session
        response.should render_template("edit")
      end
    end
  end

  describe "DELETE destroy" do
    it "destroys the requested title_type" do
      title_type = TitleType.create! valid_attributes
      expect {
        delete :destroy, {:id => title_type.to_param}, valid_session
      }.to change(TitleType, :count).by(-1)
    end

    it "redirects to the title_types list" do
      title_type = TitleType.create! valid_attributes
      delete :destroy, {:id => title_type.to_param}, valid_session
      response.should redirect_to(title_types_url)
    end
  end

end
