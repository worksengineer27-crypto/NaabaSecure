 Naaba_Secure  

 Concept

Une messagerie instantanée (messages, groupes, fichiers) pour les agents de l'administration publique, chiffrée de bout en bout et **hébergée sur une infrastructure maîtrisée**, sans aucun service tiers indispensable. Le serveur ne voit que des données chiffrées : il transporte et stocke, il ne lit rien. Les comptes sont créés uniquement par un administrateur ; il n'existe aucune inscription libre.

Nous n'avons écrit **aucune cryptographie**. Tout le chiffrement vient du protocole Matrix (Olm/Megolm), tel qu'implémenté dans Element.

Videos de demontraction:
bannir.dans.un.salon.mp4
dernier.phrase.mp4
deux.phase.de.Communication.canal.mp4
premier.phase.de.communication.peer.to.peer.mp4
verifie.si.les.serveur.lit.les.message.mp4

 Architecture

Une seule machine, quatre conteneurs Docker lancés par Docker Compose. Les navigateurs et les téléphones ne parlent qu'à Caddy.

```
Navigateur / téléphone ──HTTPS──> Caddy ──> Synapse ──> PostgreSQL
                                    └─────> Element Web
```

| Conteneur | Rôle |
|---|---|
| `caddy` | Point d'entrée unique (ports 80/443), certificat TLS interne |
| `synapse` | Serveur Matrix : comptes, salons, routage des événements chiffrés, stockage des fichiers (chiffrés par le client) |
| `db` | PostgreSQL : base de Synapse |
| `element` | Client web Element |

## Technologies et licences

| Composant | Rôle | Licence | Projet |
|---|---|---|---|
| Synapse | Serveur Matrix | AGPL-3.0 (ou licence commerciale d'Element) | https://github.com/element-hq/synapse |
| Element Web | Client web | AGPL-3.0 ou GPL-3.0 (ou licence commerciale) | https://github.com/element-hq/element-web |
| vodozemac (Olm/Megolm) | Chiffrement de bout en bout, embarqué dans Element | Apache-2.0 | https://github.com/matrix-org/vodozemac |
| PostgreSQL | Base de données | PostgreSQL License | https://www.postgresql.org |
| Caddy | Reverse proxy HTTPS | Apache-2.0 | https://github.com/caddyserver/caddy |
| Docker Compose | Orchestration des conteneurs | Apache-2.0 | https://github.com/docker/compose |

Notre code (scripts et configuration de ce dépôt) est publié sous **licence MIT** (fichier `LICENSE`).

## Niveau d'engagement : « Étendre et adapter »

Nous réutilisons Synapse et Element Web **sans modifier leur code source**. Notre apport : la configuration durcie, l'automatisation du déploiement en une commande, Nous réutilisons Synapse et Element Web sans modifier leur code source. Notre apport : la configuration durcie et l’automatisation du déploiement en une commande.

## Installation (une seule commande)

Prérequis : Ubuntu 24.04, Docker avec le plugin Compose, `curl`, droits `sudo`.

```bash
git clone https://github.com/worksengineer27-crypto/messagerie-souveraine.git
cd messagerie-souveraine
./install.sh              # ou ./install.sh <adresse-ip>
```

Le script génère le mot de passe de la base, génère et durcit la configuration de Synapse (PostgreSQL, inscription fermée, fédération coupée, aucun serveur de clés externe, rétention des messages activée), prépare Caddy et Element, démarre les services, puis crée les comptes de démonstration. Ouvrez ensuite `https://<adresse-ip>` et acceptez l'avertissement du certificat auto-signé. `./install.sh --reset` efface toutes les données et réinstalle.

## Comptes de démonstration (fictifs)

| Compte | Mot de passe | Rôle |
|---|---|---|
| `agent1` | `Demo-Agent1-2026` | Agent |
| `agent2` | `Demo-Agent2-2026` | Agent |
| `agent3` | `Demo-Agent3-2026` | Agent |
| `admin` | `Demo-Admin-2026` | Administrateur |

L'identifiant complet est de la forme `@agent1:<adresse-ip>`. Ces comptes sont fictifs et servent uniquement à la démonstration.

## Fonctionnalités et vérifications

- **Messages et groupes chiffrés de bout en bout** (Olm/Megolm) : chiffrement activé dans les salons privés.
- **Le serveur ne lit rien** : la base ne contient que des événements `m.room.encrypted`. Vérification :
  `docker compose exec db psql -U synapse -c "SELECT e.type, LEFT(j.json, 80) FROM events e JOIN event_json j USING (event_id) LIMIT 10;"`
- **Enrôlement contrôlé** : `enable_registration: false`, comptes créés par l'administrateur uniquement, fédération désactivée.
- **Fichiers chiffrés** : chiffrés par le client avant l’envoi ; vérification faite, aucun fichier n’est stocké en clair côté serveur.
- **Révocation d'un agent** : désactivation du compte par l’API d’administration de Synapse (jetons d’accès invalidés sur tous les appareils) et renouvellement de la clé de groupe. Testée : fonctionnelle.
- **Innovation** : voir « Perspectives » ci-dessous.

## Limites connues

- **Second facteur non implémenté.** Le socle l'exige ; nous le déclarons comme limite. Piste : déléguer l'authentification (OpenID Connect) à un fournisseur d'identité auto-hébergé avec TOTP.
- **Rôles limités** à deux profils : utilisateur et administrateur.
- **Métadonnées visibles par le serveur** : qui est dans quel salon, les horaires, la taille approximative des messages, les appareils et les adresses IP. Le détail et les mesures de réduction figurent dans la note de sécurité.
- **Un agent révoqué conserve ce qu'il a déjà reçu** avant sa révocation : la rotation des clés ne protège que les nouveaux messages.
- **Certificat auto-signé** : avertissement dans le navigateur ; une application mobile peut le refuser tant que le certificat racine de Caddy n'est pas installé sur l'appareil.
- **Nom du serveur lié à l'adresse IP** choisie à l'installation : changer d'adresse impose une réinstallation (`./install.sh --reset`).
- Perspectives

Innovation : niveaux de confidentialité des messages. Salons « Diffusion restreinte » et « Confidentiel » avec expiration automatique, appuyés sur la rétention déjà activée par install.sh. En cours de développement, non encore fonctionnelle.
