defmodule Goodtap.CatalogTest do
  use Goodtap.DataCase, async: true

  alias Goodtap.Catalog
  alias Goodtap.Catalog.Card

  defp insert_card!(attrs) do
    defaults = %{
      layout: "normal",
      is_token: false,
      data: %{},
      printings: [],
      default_printing_id: nil
    }

    merged = Map.merge(defaults, attrs)

    %Card{}
    |> Ecto.Changeset.change(merged)
    |> Repo.insert!()
  end

  describe "find_card_for_deck/1 with split/DFC cards" do
    test "finds split card by front face when other cards share the prefix" do
      insert_card!(%{id: "dead-gone", name: "Dead // Gone", layout: "split"})
      insert_card!(%{id: "dead-weight", name: "Dead Weight", layout: "normal"})
      insert_card!(%{id: "dead-revels", name: "Dead Revels", layout: "normal"})

      {card, _printing_id} = Catalog.find_card_for_deck("Dead // Gone")
      assert card.id == "dead-gone"

      {card, _printing_id} = Catalog.find_card_for_deck("Dead")
      assert card.id == "dead-gone"
    end

    test "returns nil when multiple cards share front face name" do
      insert_card!(%{id: "dead-gone", name: "Dead // Gone", layout: "split"})
      insert_card!(%{id: "dead-other", name: "Dead // Other", layout: "split"})

      {card, _printing_id} = Catalog.find_card_for_deck("Dead")
      assert card == nil
    end

    test "still finds unique prefix match" do
      insert_card!(%{id: "modern-age", name: "The Modern Age // Vector Glider", layout: "transform"})

      {card, _printing_id} = Catalog.find_card_for_deck("The Modern Age")
      assert card.id == "modern-age"
    end

    test "finds exact match even with prefix collisions" do
      insert_card!(%{id: "dead-weight", name: "Dead Weight", layout: "normal"})
      insert_card!(%{id: "dead-gone", name: "Dead // Gone", layout: "split"})

      {card, _printing_id} = Catalog.find_card_for_deck("Dead Weight")
      assert card.id == "dead-weight"
    end

    test "finds split card via single slash format (Dead / Gone)" do
      insert_card!(%{id: "dead-gone", name: "Dead // Gone", layout: "split"})
      insert_card!(%{id: "dead-weight", name: "Dead Weight", layout: "normal"})
      insert_card!(%{id: "dead-revels", name: "Dead Revels", layout: "normal"})

      {card, _printing_id} = Catalog.find_card_for_deck("Dead / Gone")
      assert card.id == "dead-gone"
    end
  end

  describe "find_cards_for_deck/1 bulk with split/DFC cards" do
    test "finds split card by front face in bulk lookup" do
      insert_card!(%{id: "dead-gone", name: "Dead // Gone", layout: "split"})
      insert_card!(%{id: "dead-weight", name: "Dead Weight", layout: "normal"})

      results = Catalog.find_cards_for_deck([
        %{name: "Dead // Gone", set_code: nil, collector_number: nil},
        %{name: "Dead Weight", set_code: nil, collector_number: nil}
      ])

      {card1, _} = results["Dead // Gone"]
      assert card1.id == "dead-gone"

      {card2, _} = results["Dead Weight"]
      assert card2.id == "dead-weight"
    end

    test "finds split card via single slash in bulk lookup" do
      insert_card!(%{id: "dead-gone", name: "Dead // Gone", layout: "split"})
      insert_card!(%{id: "dead-weight", name: "Dead Weight", layout: "normal"})

      results = Catalog.find_cards_for_deck([
        %{name: "Dead / Gone", set_code: nil, collector_number: nil}
      ])

      {card1, _} = results["Dead / Gone"]
      assert card1.id == "dead-gone"
    end
  end

  describe "plaintext importer with split cards" do
    alias Goodtap.Decks.Importers.Plaintext

    test "parses Dead // Gone from decklist and resolves the card" do
      insert_card!(%{id: "dead-gone", name: "Dead // Gone", layout: "split"})
      insert_card!(%{id: "dead-weight", name: "Dead Weight", layout: "normal"})

      {:ok, deck_data} = Plaintext.import("Test", "4 Dead // Gone\n2 Dead Weight")

      names = Enum.map(deck_data.cards, & &1.name)
      assert "Dead // Gone" in names
      assert "Dead Weight" in names

      # Verify catalog lookup works for each parsed name
      for entry <- deck_data.cards do
        {card, _} = Catalog.find_card_for_deck(entry.name)
        assert card != nil, "Expected to find card for #{entry.name}"
      end
    end

    test "parses Dead / Gone from decklist and resolves the card" do
      insert_card!(%{id: "dead-gone", name: "Dead // Gone", layout: "split"})
      insert_card!(%{id: "dead-weight", name: "Dead Weight", layout: "normal"})

      {:ok, deck_data} = Plaintext.import("Test", "4 Dead / Gone")

      [entry] = deck_data.cards
      assert entry.name == "Dead / Gone"

      {card, _} = Catalog.find_card_for_deck(entry.name)
      assert card.id == "dead-gone"
    end
  end
end
