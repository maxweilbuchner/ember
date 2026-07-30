// RelationResolverTests.swift

import Foundation
import Testing
@testable import Ember

@Suite("Relation resolver")
struct RelationResolverTests {
    private let annaID = UUID()
    private let tomID = UUID()
    private let otherAnnaID = UUID()

    private var people: [NameCandidate] {
        [
            RelationResolver.candidate(personID: annaID, displayName: "Anna Schmid"),
            RelationResolver.candidate(personID: tomID, displayName: "Tom Schmid"),
        ]
    }

    private func relation(_ label: String, _ name: String) -> ContactRelationItem {
        ContactRelationItem(rawLabel: "_$!<\(label)>!$_", localizedLabel: label, name: name)
    }

    // MARK: Related names on the person's own card

    @Test func uniqueNameMatchLinks() {
        let links = RelationResolver.related(
            relations: [relation("Spouse", "Tom Schmid")],
            people: people,
            excludingPersonID: annaID
        )
        #expect(links.count == 1)
        #expect(links.first?.linkedPersonID == tomID)
        #expect(links.first?.localizedLabel == "Spouse")
    }

    @Test func ambiguousNameStaysUnlinkedText() {
        var crowded = people
        crowded.append(RelationResolver.candidate(personID: otherAnnaID, displayName: "Anna Berger"))
        let links = RelationResolver.related(
            relations: [relation("Sister", "Anna")],
            people: crowded,
            excludingPersonID: tomID
        )
        #expect(links.count == 1, "the row still shows — it just doesn't link")
        #expect(links.first?.linkedPersonID == nil)
        #expect(links.first?.name == "Anna")
    }

    @Test func selfIsExcludedFromMatching() {
        let links = RelationResolver.related(
            relations: [relation("Friend", "Anna Schmid")],
            people: people,
            excludingPersonID: annaID
        )
        #expect(links.first?.linkedPersonID == nil, "a card listing the person's own name must not self-link")
    }

    @Test func diacriticAndCaseInsensitiveMatching() {
        let people = [RelationResolver.candidate(personID: tomID, displayName: "Tomáš Novák")]
        let links = RelationResolver.related(
            relations: [relation("Brother", "tomas novak")],
            people: people,
            excludingPersonID: annaID
        )
        #expect(links.first?.linkedPersonID == tomID)
    }

    @Test func customLabelStringsPassThrough() {
        let item = ContactRelationItem(rawLabel: "sensei", localizedLabel: "sensei", name: "Tom Schmid")
        let links = RelationResolver.related(relations: [item], people: people, excludingPersonID: annaID)
        #expect(links.first?.localizedLabel == "sensei")
        #expect(links.first?.linkedPersonID == tomID)
    }

    // MARK: Relation-to-you from the me card

    @Test func meCardLabelsThePersonOnUniqueMatch() {
        let label = RelationResolver.labelForPerson(
            personID: annaID,
            meRelations: [relation("Mother", "Anna Schmid")],
            people: people
        )
        #expect(label == "Mother")
    }

    @Test func meCardLabelRequiresUniqueMatch() {
        var crowded = people
        crowded.append(RelationResolver.candidate(personID: otherAnnaID, displayName: "Anna Berger"))
        let label = RelationResolver.labelForPerson(
            personID: annaID,
            meRelations: [relation("Mother", "Anna")],
            people: crowded
        )
        #expect(label == nil, "two Annas → no label rather than a wrong one")
    }

    @Test func meCardLabelForOtherPersonGivesNil() {
        let label = RelationResolver.labelForPerson(
            personID: tomID,
            meRelations: [relation("Mother", "Anna Schmid")],
            people: people
        )
        #expect(label == nil)
    }

    @Test func emptyMeCardGivesNoLabel() {
        #expect(RelationResolver.labelForPerson(personID: annaID, meRelations: [], people: people) == nil)
    }
}
