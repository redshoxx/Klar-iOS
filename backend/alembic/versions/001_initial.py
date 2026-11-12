"""initial versioned account and synchronization schema

Revision ID: 001_initial
Revises:
"""
from alembic import op
import sqlalchemy as sa
revision = '001_initial'
down_revision = None
branch_labels = None
depends_on = None

def upgrade():
    op.create_table('users', sa.Column('id', sa.String(36), primary_key=True),
                    sa.Column('email', sa.String(320), nullable=False),
                    sa.Column('password_hash', sa.Text(), nullable=False),
                    sa.Column('created_at', sa.DateTime(timezone=True), nullable=False))
    op.create_index('ix_users_email', 'users', ['email'], unique=True)
    op.create_table('session_tokens', sa.Column('token_hash', sa.String(64), primary_key=True),
                    sa.Column('user_id', sa.String(36), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
                    sa.Column('kind', sa.String(16), nullable=False),
                    sa.Column('expires_at', sa.DateTime(timezone=True), nullable=False),
                    sa.Column('revoked', sa.Boolean(), nullable=False),
                    sa.Column('created_at', sa.DateTime(timezone=True), nullable=False))
    op.create_index('ix_session_tokens_user_id','session_tokens',['user_id'])
    op.create_table('records', sa.Column('user_id', sa.String(36), sa.ForeignKey('users.id', ondelete='CASCADE'), primary_key=True),
                    sa.Column('kind', sa.String(32), primary_key=True),
                    sa.Column('id', sa.String(36), primary_key=True),
                    sa.Column('version', sa.Integer(), nullable=False),
                    sa.Column('data', sa.JSON(), nullable=False),
                    sa.Column('deleted', sa.Boolean(), nullable=False),
                    sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False))
    op.create_table('changes', sa.Column('seq', sa.Integer(), primary_key=True, autoincrement=True),
                    sa.Column('user_id', sa.String(36), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
                    sa.Column('kind', sa.String(32), nullable=False),
                    sa.Column('id', sa.String(36), nullable=False),
                    sa.Column('version', sa.Integer(), nullable=False),
                    sa.Column('data', sa.JSON(), nullable=False),
                    sa.Column('deleted', sa.Boolean(), nullable=False),
                    sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False))
    op.create_index('ix_changes_user_seq','changes',['user_id','seq'])
    op.create_table('login_failures', sa.Column('id', sa.Integer(), primary_key=True, autoincrement=True),
                    sa.Column('account_key', sa.String(64), nullable=False),
                    sa.Column('created_at', sa.DateTime(timezone=True), nullable=False))
    op.create_index('ix_login_failures_account_key','login_failures',['account_key'])

def downgrade():
    for t in ['login_failures','changes','records','session_tokens','users']:
        op.drop_table(t)
