
CREATE TABLE IF NOT EXISTS  Peers(
    Nickname VARCHAR NOT NULL PRIMARY KEY,
    Birthday DATE NOT NULL
);

CREATE TABLE IF NOT EXISTS TimeTracking(
    ID SERIAL NOT NULL PRIMARY KEY,
    Peer VARCHAR NOT NULL,
    "Date" DATE NOT NULL,
    "Time" TIME NOT NULL,
    "State" CHAR NOT NULL,
    CONSTRAINT ch_time_tracking_state CHECK ("State" IN ('1', '2')),
    CONSTRAINT fk_time_tracking_peer FOREIGN KEY(Peer) REFERENCES Peers(Nickname)  
);

CREATE TABLE IF NOT EXISTS Recommendations(
    ID SERIAL NOT NULL PRIMARY KEY,
    Peer VARCHAR NOT NULL,
    RecommendedPeer VARCHAR NOT NULL,
    CONSTRAINT fk_recommendations_peer FOREIGN KEY(Peer) REFERENCES Peers(Nickname),
    CONSTRAINT fk_recommendations_recommended_peer FOREIGN KEY(RecommendedPeer) REFERENCES Peers(Nickname),
    CONSTRAINT ch_recommendations_peer_recommended_peer CHECK (Peer != RecommendedPeer)
);

CREATE TABLE IF NOT EXISTS Friends(
    ID SERIAL NOT NULL PRIMARY KEY,
    Peer1 VARCHAR NOT NULL,
    Peer2 VARCHAR NOT NULL,
    CONSTRAINT fk_friends_peer1 FOREIGN KEY(Peer1) REFERENCES Peers(Nickname),
    CONSTRAINT fk_friends_peer2 FOREIGN KEY(Peer2) REFERENCES Peers(Nickname),
    CONSTRAINT ch_friends_peer1_peer2 CHECK (Peer1 != Peer2)
);

CREATE TABLE IF NOT EXISTS TransferredPoints(
    ID SERIAL NOT NULL PRIMARY KEY,
    CheckingPeer VARCHAR NOT NULL,
    CheckedPeer VARCHAR NOT NULL,
    PointsAmount INT NOT NULL DEFAULT 0,
    CONSTRAINT fk_transferred_points_checking_peer FOREIGN KEY(CheckingPeer) REFERENCES Peers(Nickname),
    CONSTRAINT fk_transferred_points_checked_peer FOREIGN KEY(CheckedPeer) REFERENCES Peers(Nickname),
    CONSTRAINT ch_transferred_points_checking_peer_checked_peer CHECK (CheckingPeer != CheckedPeer)
);


CREATE TABLE IF NOT EXISTS  Tasks(
    Title VARCHAR NOT NULL PRIMARY KEY,
    ParentTask VARCHAR,
    MaxXP INT NOT NULL
);

CREATE TABLE IF NOT EXISTS Checks(
    ID SERIAL NOT NULL PRIMARY KEY, 
    Peer VARCHAR NOT NULL,
    Task VARCHAR NOT NULL,
    Date DATE NOT NULL,
    CONSTRAINT fk_checks_peer FOREIGN KEY(Peer) REFERENCES Peers(Nickname),
    CONSTRAINT fk_checks_task FOREIGN KEY(Task) REFERENCES Tasks(Title)
);

CREATE TABLE IF IF NOT EXISTS XP(
    ID SERIAL PRIMARY KEY,
    "Check" BIGINT NOT NULL,
    XPAmount BIGINT NOT NULL,
    CONSTRAINT fk_xp_check FOREIGN KEY ("Check") REFERENCES Checks(ID),
    CONSTRAINT ch_xp_xp_amout CHECK (XPAmount >= 0) 
); 

CREATE TYPE check_status AS ENUM ('Start', 'Success', 'Failure');

CREATE TABLE IF IF NOT EXISTS Verter(
    ID SERIAL PRIMARY KEY,
    "Check" BIGINT NOT NULL,
    "State" check_status NOT NULL,
    "Time" TIME NOT NULL,
    CONSTRAINT fk_verter_check FOREIGN KEY ("Check") REFERENCES Checks(ID)
); 

CREATE TABLE IF IF NOT EXISTS P2P(
    ID SERIAL PRIMARY KEY,
    "Check" BIGINT NOT NULL,
    CheckingPeer VARCHAR NOT NULL, 
    "State" check_status NOT NULL,
    "Time" TIME NOT NULL,
    CONSTRAINT fk_p2p_check FOREIGN KEY ("Check") REFERENCES Checks(ID),
    CONSTRAINT fk_p2p_checking_peer FOREIGN KEY ("CheckingPeer") REFERENCES Peers(Nickname)
); 