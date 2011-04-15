require 'spec_helper'

describe CheckinsController do
  fixtures :all

  def mock_user(stubs={})
    (@mock_user ||= mock_model(Checkin).as_null_object).tap do |user|
      user.stub(stubs) unless stubs.empty?
    end
  end

  describe "GET index" do
    describe "When logged in as Administrator" do
      before(:each) do
        sign_in Factory(:admin)
      end

      it "assigns all checkins as @checkins" do
        get :index
        assigns(:checkins).should eq(Checkin.all)
        response.should redirect_to(user_basket_checkins_url(assigns(:basket).user, assigns(:basket)))
      end

      describe "When basket_id is specified" do
        it "assigns all checkins as @checkins" do
          get :index, :basket_id => 1
          assigns(:checkins).should eq(assigns(:basket).checkins)
          response.should be_success
        end
      end
    end

    describe "When logged in as Librarian" do
      before(:each) do
        sign_in Factory(:librarian)
      end

      it "assigns all checkins as @checkins" do
        get :index
        assigns(:checkins).should eq(Checkin.all)
        response.should redirect_to(user_basket_checkins_url(assigns(:basket).user, assigns(:basket)))
      end

      describe "When basket_id is specified" do
        it "assigns all checkins as @checkins" do
          get :index, :basket_id => 1
          assigns(:checkins).should eq(assigns(:basket).checkins)
          response.should be_success
        end
      end
    end

    describe "When logged in as User" do
      before(:each) do
        sign_in Factory(:user)
      end

      it "should not assign all checkins as @checkins" do
        get :index
        assigns(:checkins).should be_empty
        response.should be_forbidden
      end
    end
  end

  describe "POST create" do
    before(:each) do
      sign_in Factory(:admin)
      @attrs = {:item_identifier => '00003'}
      @invalid_attrs = {:item_identifier => 'invalid'}
    end

    describe "with valid params" do
      it "assigns a newly created checkin as @checkin" do
        post :create, :checkin => @attrs
        assigns(:checkin).should be_valid
      end

      it "redirects to index" do
        post :create, :checkin => @attrs
        response.should redirect_to(user_basket_checkins_url(assigns(:basket).user, assigns(:basket)))
        assigns(:checkin).item.circulation_status.name.should eq 'Available On Shelf'
      end

      describe "When basket_id is specified" do
        it "redirects to the created checkin" do
          post :create, :checkin => @attrs, :basket_id => 9
          response.should redirect_to(user_basket_checkins_url(assigns(:basket).user, assigns(:basket)))
          assigns(:checkin).item.circulation_status.name.should eq 'Available On Shelf'
        end
      end
    end

    describe "with invalid params" do
      it "assigns a newly created but unsaved checkin as @checkin" do
        post :create, :checkin => @invalid_attrs
        assigns(:checkin).should be_valid
      end

      it "redirects to the list" do
        post :create, :checkin => @invalid_attrs
        response.should redirect_to(user_basket_checkins_url(assigns(:basket).user, assigns(:basket)))
      end
    end
  end
end
